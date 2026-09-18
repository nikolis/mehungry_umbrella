defmodule Mehungry.Professionals.DietaryHistory.CsvParser do
  @moduledoc """
  Pure parsing of a nutritionist's "ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ" (dietary history)
  Google-Sheet CSV export into structured attrs. No IO or DB happens here — the
  `DietaryHistory.Importer` flows through `parse/1`.

  The sheet is two stacked sections:

    1. An intake questionnaire (Appointment 1) — a flat `label,value` grid of
       identity, anthropometrics, medical history, lifestyle, eating behavior and
       a 24-hour recall.
    2. A per-visit progress log (Appointment 2…N) — one free-text block each,
       opened by a `ΗΜΕΡ/ΝΙΑ: <weekday date>, ΡΑΝΤΕΒΟΥ <n>, <modality>` header.

  `parse/1` returns

      {:ok, %{client: map, intake: map, consultation_notes: [map, ...]}} | {:error, reason}

  Numbers use EU comma-decimals ("1,75") and dates are Greek ("Δευτέρα 15/09/2025").
  """

  alias NimbleCSV.RFC4180, as: CSV

  # Intake label (normalized) → routing instruction:
  #   {:client, field}         → ProfessionalClient attr
  #   {:client_date, field}    → ProfessionalClient date attr
  #   {:float, field}          → typed ClientIntake float (comma-decimal)
  #   {:int, field}            → typed ClientIntake integer
  #   {:string, field}         → typed ClientIntake string
  #   {:details, key}          → intake.details[key]
  #   {:recall, key}           → intake.details.recall_24h[key]
  @intake_fields %{
    "ΟΝΟΜΑΤΕΠΩΝΥΜΟ:" => {:client, :full_name},
    "ΗΛΙΚΙΑ:" => {:details, "age"},
    "ΗΜΕΡ/ΝΙΑ ΓΕΝΝΗΣΗΣ:" => {:client_date, :date_of_birth},
    "ΔΙΕΥΘΥΝΣΗ:" => {:client, :address},
    "Τ.Κ.:" => {:client, :postal_code},
    "ΤΗΛΕΦΩΝΟ:" => {:client, :phone},
    "Email:" => {:client, :email},
    "ΕΡΓΑΣΙΑ/ ΩΡΑΡΙΟ:" => {:client, :work_schedule},
    "ΥΨΟΣ:" => {:float, :height_m},
    "ΒΑΡΟΣ:" => {:float, :weight_kg},
    "ΒΜΙ:" => {:float, :bmi},
    "ΣΥΝΗΘΕΣ ΒΑΡΟΣ:" => {:float, :usual_weight_kg},
    "ΙΔΑΝΙΚΟ ΒΑΡΟΣ (Lorentz):" => {:float, :ideal_weight_kg},
    "ΔΙΟΡΘΩΜΕΝΟ ΒΑΡΟΣ:" => {:float, :adjusted_weight_kg},
    "ΔΙΑΚΥΜΑΝΣΕΙΣ ΒΑΡΟΥΣ:" => {:details, "weight_fluctuations"},
    "ΑΙΤΙΟ ΠΡΟΣΕΛΕΥΣΗΣ:" => {:details, "reason_for_visit"},
    "ΟΙΚΟΓΕΝΕΙΑΚΗ ΚΑΤΑΣΤΑΣΗ:" => {:details, "marital_status"},
    "ΓΕΓΟΝΟΣ ΣΤΑΘΜΟΣ:" => {:details, "milestone_events"},
    "ΑΠΟΠΕΙΡΕΣ ΕΠΙΛΥΣΗΣ ΠΡΟΒΛΗΜΑΤΟΣ:" => {:details, "past_attempts"},
    "ΟΙΚΟΓΕΝΕΙΑΚΟ ΙΣΤΟΡΙΚΟ ΒΑΡΟΥΣ (Γονείς, Αδέρφια, Παιδιά):" =>
      {:details, "family_weight_history"},
    "ΚΛΗΡΟΝΟΜΙΚΟ ΙΣΤΟΡΙΚΟ ΧΡΟΝΙΩΝ ΝΟΣΗΜΑΤΩΝ:" => {:details, "hereditary_conditions"},
    "ΓΑΣΤΡΕΝΤΕΡΙΚΗ ΛΕΙΤΟΥΡΓΙΑ:" => {:details, "gi_function"},
    "ΧΡΗΣΗ ΦΑΡΜΑΚΩΝ:" => {:details, "medications"},
    "ΒΙΟΧΗΜΙΚΗ ΑΙΜΑΤΟΣ:" => {:details, "blood_biochem"},
    "ΕΞΕΤΑΣΕΙΣ ΘΥΡΕΟΕΙΔΗ:" => {:details, "thyroid_tests"},
    "ΓΥΝΑΙΚΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ (εγκυμοσύνες, επεμβάσεις):" => {:details, "gynecological_history"},
    "ΑΛΛΕΡΓΙΕΣ:" => {:details, "allergies"},
    "ΑΛΚΟΟΛ:" => {:details, "alcohol"},
    "ΥΓΡΑ:" => {:details, "fluids"},
    "ΚΑΠΝΙΣΜΑ:" => {:details, "smoking"},
    "ΥΠΝΟΣ (ΩΡΕΣ – ΠΟΙΟΤΗΤΑ):" => {:details, "sleep"},
    "ΦΥΣΙΚΗ ΔΡΑΣΤΗΡΙΟΤΗΤΑ:" => {:details, "physical_activity"},
    "ΤΡΟΦΙΚΕΣ ΕΝΟΧΛΗΣΕΙΣ:" => {:details, "food_intolerances"},
    "ΤΡΟΦΙΚΕΣ ΑΠΕΧΘΙΕΣ:" => {:details, "food_aversions"},
    "ΙΔΙΑΙΤΕΡΕΣ ΔΙΑΤΡΟΦΙΚΕΣ ΣΥΝΗΘΕΙΕΣ:" => {:details, "special_eating_habits"},
    "ΣΤΟΧΟΣ:" => {:string, :goal},
    "ΑΣΥΝΕΙΔΗΤΗ – ΑΣΚΟΠΗ ΔΙΑΤΡΟΦΗ:" => {:details, "unconscious_eating"},
    "ΣΥΝΑΙΣΘΗΜΑΤΙΚΗ ΥΠΕΡΦΑΓΙΑ:" => {:details, "emotional_overeating"},
    "ΥΠΕΡΚΑΤΑΝΑΛΩΣΗ:" => {:details, "overconsumption"},
    "ΑΞΙΟΛΟΓΗΣΗ ΠΡΟΣΔΟΚΙΩΝ ΓΙΑ ΤΗΝ ΕΠΙΤΕΥΞΗ ΣΤΟΧΟΥ:" => {:details, "expectations_assessment"},
    "ΔΙΚΑΙΟΛΟΓΗΣΗ ΑΙΤΙΟΥ ΠΡΟΕΛΕΥΣΗΣ:" => {:details, "reason_justification"},
    "ΠΑΡΑΤΗΡΗΣΕΙΣ – ΣΥΣΤΑΣΕΙΣ:" => {:details, "observations"},
    "Πρωινό:" => {:recall, "breakfast"},
    "Δεκατιανό:" => {:recall, "mid_morning"},
    "Μεσημεριανό:" => {:recall, "lunch"},
    "Απογευματινό:" => {:recall, "afternoon"},
    "Βραδινό:" => {:recall, "dinner"},
    "Κατανάλωση λαχανικών:" => {:recall, "vegetable_intake"},
    "Κατανάλωση φρούτων:" => {:recall, "fruit_intake"},
    "GEB: Kcal" => {:int, :bmr_kcal},
    "GET: kcal" => {:int, :tdee_kcal},
    "Σημειώσεις:" => {:details, "notes"}
  }

  @header_re ~r/^\s*ΗΜΕΡ\/ΝΙΑ:/u
  @date_re ~r|(\d{1,2})/(\d{1,2})/(\d{4})|
  @int_re ~r/(\d+)/
  @todo_re ~r/^\s*Σημειώσεις/u

  @doc "Parses a full dietary-history CSV string. See moduledoc for the return shape."
  def parse(content) when is_binary(content) do
    rows = CSV.parse_string(content, skip_headers: false)

    case split_blocks(rows) do
      [] ->
        {:error, :no_appointments}

      [intake_block | note_blocks] ->
        {client, intake} = parse_intake(intake_block)
        notes = Enum.map(note_blocks, &parse_note/1)
        {:ok, %{client: client, intake: intake, consultation_notes: notes}}
    end
  end

  # ── Section splitting ───────────────────────────────────────────────────────────

  # Drop the preamble (title rows) then chunk on each ΗΜΕΡ/ΝΙΑ header.
  defp split_blocks(rows) do
    rows
    |> Enum.drop_while(&(not header_row?(&1)))
    |> chunk_on_header()
  end

  defp chunk_on_header([]), do: []

  defp chunk_on_header([header | rest]) do
    {block_rest, tail} = Enum.split_while(rest, &(not header_row?(&1)))
    [[header | block_rest] | chunk_on_header(tail)]
  end

  defp header_row?(row), do: Regex.match?(@header_re, cell(row, 0))

  # ── Intake block ────────────────────────────────────────────────────────────────

  defp parse_intake([header | rows]) do
    init_intake = %{assessed_on: parse_greek_date(cell(header, 0)), details: %{}}

    {client, intake} =
      Enum.reduce(rows, {%{}, init_intake}, fn row, {client, intake} ->
        label = normalize(cell(row, 0))
        value = non_empty(cell(row, 1))
        route_intake(Map.get(@intake_fields, label), value, client, intake)
      end)

    {client, intake}
  end

  defp route_intake(nil, _value, client, intake), do: {client, intake}
  defp route_intake(_route, nil, client, intake), do: {client, intake}

  defp route_intake({:client, field}, value, client, intake),
    do: {Map.put(client, field, value), intake}

  defp route_intake({:client_date, field}, value, client, intake),
    do: {Map.put(client, field, parse_greek_date(value)), intake}

  defp route_intake({:float, field}, value, client, intake),
    do: {client, Map.put(intake, field, to_decimal_float(value))}

  defp route_intake({:int, field}, value, client, intake),
    do: {client, Map.put(intake, field, to_int(value))}

  defp route_intake({:string, field}, value, client, intake),
    do: {client, Map.put(intake, field, value)}

  defp route_intake({:details, key}, value, client, intake),
    do: {client, put_in_details(intake, [key], value)}

  defp route_intake({:recall, key}, value, client, intake),
    do: {client, put_in_details(intake, ["recall_24h", key], value)}

  # Deep-put into the string-keyed `details` map (recall lives one level down).
  defp put_in_details(intake, [key], value) do
    Map.update!(intake, :details, &Map.put(&1, key, value))
  end

  defp put_in_details(intake, [group, key], value) do
    Map.update!(intake, :details, fn details ->
      Map.update(details, group, %{key => value}, &Map.put(&1, key, value))
    end)
  end

  # ── Note block ──────────────────────────────────────────────────────────────────

  defp parse_note([header | rows]) do
    {todo_rows, body_rows} = Enum.split_with(rows, &todo_row?/1)

    body =
      body_rows
      |> Enum.map(&cell(&1, 0))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> case do
        [] -> nil
        parts -> Enum.join(parts, "\n\n")
      end

    todo =
      todo_rows
      |> Enum.map(&non_empty(cell(&1, 1)))
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        parts -> Enum.join(parts, "\n\n")
      end

    %{
      visit_number: parse_visit_number(cell(header, 1)),
      visit_date: parse_greek_date(cell(header, 0)),
      modality: detect_modality(cell(header, 2)),
      body: body,
      todo: todo,
      details: %{}
    }
  end

  defp todo_row?(row), do: Regex.match?(@todo_re, cell(row, 0))

  # ── Coercion helpers ────────────────────────────────────────────────────────────

  # Nutritionist sheets use EU comma-decimals: "1,75" → 1.75, "80" → 80.0.
  # No existing helper handles this (all other parsers assume dot-decimals).
  defp to_decimal_float(value) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") |> Float.parse() do
      {float, _rest} -> float
      :error -> nil
    end
  end

  defp to_decimal_float(_), do: nil

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp to_int(_), do: nil

  # "ΡΑΝΤΕΒΟΥ 7" → 7; nil when no digits present.
  defp parse_visit_number(cell) do
    case Regex.run(@int_re, cell || "") do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  # "Δευτέρα 15/09/2025" → ~D[2025-09-15]; weekday word and stray spaces ignored.
  defp parse_greek_date(cell) do
    with [_, d, m, y] <- Regex.run(@date_re, cell || ""),
         {:ok, date} <- Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      date
    else
      _ -> nil
    end
  end

  # Modality from the header's 3rd cell: phone / online / (default) in_person.
  defp detect_modality(cell) do
    down = cell |> to_string() |> String.downcase()

    cond do
      String.contains?(down, "τηλεφ") -> "phone"
      String.contains?(down, "online") -> "online"
      true -> "in_person"
    end
  end

  defp normalize(value) do
    value |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim()
  end

  defp non_empty(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_empty(_), do: nil

  # Safe positional cell access — rows may be short when trailing commas are absent.
  defp cell(row, index) when is_list(row), do: Enum.at(row, index, "") || ""
  defp cell(_row, _index), do: ""
end
