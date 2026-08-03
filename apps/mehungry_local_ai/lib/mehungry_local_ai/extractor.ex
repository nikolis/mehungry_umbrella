defmodule MehungryLocalAi.Extractor do
  @moduledoc """
  Extracts quantitative compound measurements from a study's text as findings.

  Pure NLP — no database, no species knowledge. The server fans each finding out
  across the species linked to the study and persists them as review-gated candidates.

  Hybrid, degrading gracefully:

    * **QA-primary** — when `MehungryLocalAi.QA` is loaded, ask "How much <compound>
      does it contain?" over the text and parse a value+unit from the answer span,
      using the model's confidence as the score.
    * **Rule-based fallback** — when QA is unavailable (tests), find number+unit spans
      near the compound name (the benchmarked regex approach).
  """

  alias MehungryLocalAi.QA

  # Concentration-like units (mass/mass, mass/volume) + bare percent.
  @value_rx ~r/(\d+(?:\.\d+)?)\s?(?:mg|g|µg|μg|ug|kg)\s?\/\s?(?:100\s?g|100\s?mL|kg|g|mL|L)|(\d+(?:\.\d+)?)\s?%/i
  @method_rx ~r/\b(HPLC|UPLC|LC-?MS(?:\/MS)?|GC-?MS|GC|LC|spectrophotometr\w*|colorimetr\w*|titration|ICP-?MS|NMR|Folin[-\s]?Ciocalteu)\b/i
  @prep_words ~w(raw cooked boiled steamed roasted fried dried fresh frozen fermented baked blanched pickled)

  @rule_score 0.4

  @doc """
  Extract measurement findings from `text` for each of `compounds`
  (`[%{id, name, synonyms}]`). Returns a flat list of finding maps ready to POST:
  `%{compound_id, value, unit, preparation_method, analytical_method, score,
  raw_span, extraction_method}`.
  """
  def findings(text, compounds) when is_binary(text) and text != "" and is_list(compounds) do
    for compound <- compounds,
        finding <- findings_for(text, compound) do
      Map.put(finding, :compound_id, compound.id)
    end
  end

  def findings(_text, _compounds), do: []

  # ── Findings per compound ────────────────────────────────────────────────

  defp findings_for(text, compound) do
    if QA.available?() do
      case qa_finding(text, compound) do
        nil -> []
        finding -> [finding]
      end
    else
      rule_findings(text, compound)
    end
  end

  defp qa_finding(text, compound) do
    question = "How much #{compound.name} does it contain?"

    with %{text: answer, score: score} <- QA.answer(question, text),
         [frag | _] <- Regex.run(@value_rx, answer),
         {value, unit} when not is_nil(value) <- split_value_unit(String.trim(frag)),
         span = sentence_containing(text, String.trim(frag)),
         true <- composition_context?(span) do
      %{
        value: value,
        unit: unit,
        preparation_method: find_prep(answer),
        analytical_method: find_method(text),
        raw_span: span,
        score: Float.round(score, 3),
        extraction_method: "automated"
      }
    else
      _ -> nil
    end
  end

  defp rule_findings(text, compound) do
    low = String.downcase(text)
    method = find_method(text)

    name_positions =
      [compound.name | compound.synonyms || []]
      |> Enum.reject(&(is_nil(&1) or String.length(&1) < 3))
      |> Enum.flat_map(fn n -> :binary.matches(low, String.downcase(n)) |> Enum.map(&elem(&1, 0)) end)

    if name_positions == [] do
      []
    else
      Regex.scan(@value_rx, text, return: :index)
      |> Enum.flat_map(fn idxs ->
        {pos, len} = hd(idxs)
        frag = binary_part(text, pos, len)

        if Enum.min(Enum.map(name_positions, &abs(&1 - pos))) <= 160 do
          span = sentence_containing(text, frag)

          case split_value_unit(String.trim(frag)) do
            {value, unit} when not is_nil(value) ->
              if composition_context?(span) do
                [
                  %{
                    value: value,
                    unit: unit,
                    preparation_method: find_prep(window(low, pos)),
                    analytical_method: method,
                    raw_span: span,
                    score: @rule_score,
                    extraction_method: "automated"
                  }
                ]
              else
                []
              end

            _ ->
              []
          end
        else
          []
        end
      end)
      |> Enum.uniq_by(&{&1.value, &1.unit})
    end
  end

  # ── Parsing helpers ──────────────────────────────────────────────────────

  defp split_value_unit(frag) do
    case Regex.run(~r/^\s*(\d+(?:\.\d+)?)\s*(.+?)\s*$/u, frag) do
      [_, num, unit] -> {parse_float(num), Regex.replace(~r/\s+/u, unit, " ")}
      _ -> {nil, nil}
    end
  end

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp find_method(text) do
    case Regex.run(@method_rx, text) do
      [m | _] -> m
      _ -> nil
    end
  end

  defp find_prep(window), do: Enum.find(@prep_words, &String.contains?(window, &1))

  # The sentence in `text` that contains `needle` (the extracted value token) — the
  # human-readable context that says what the bare number actually refers to, so a
  # reviewer can tell "40% of headspace gas" from a real "40 mg/100g" composition.
  # Falls back to the needle itself when no sentence match is found.
  # Reject values whose sentence describes a change/emission/inhibition rather than a
  # static composition — "reduced by 40%", "methane emission", "headspace gas". These
  # are the classic false positives (e.g. Alfalfa · Methane 40%). Heuristic, so it
  # pairs with the source sentence now shown in review for the ones that slip through.
  @noncomposition_rx ~r/\b(emissions?|headspace|inhibit\w*|mitigat\w*|excret\w*)\b|\b(reduc\w+|decreas\w+|increas\w+|declin\w+)\s+(by|of|to|from)\b/i

  defp composition_context?(span) when span in [nil, ""], do: true
  defp composition_context?(span), do: not Regex.match?(@noncomposition_rx, span)

  @max_context 300
  defp sentence_containing(_text, needle) when needle in [nil, ""], do: needle

  defp sentence_containing(text, needle) do
    text
    |> String.split(~r/(?<=[.!?])\s+|\n+/u, trim: true)
    |> Enum.find(&String.contains?(&1, needle))
    |> case do
      nil -> String.slice(needle, 0, @max_context)
      sentence -> sentence |> String.trim() |> String.slice(0, @max_context)
    end
  end

  defp window(low, pos) do
    start = max(pos - 90, 0)
    binary_part(low, start, min(200, byte_size(low) - start))
  end
end
