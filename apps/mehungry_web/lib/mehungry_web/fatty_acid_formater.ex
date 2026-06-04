defmodule MehungryWeb.FattyAcidFormatter do
  @moduledoc """
  Formats fatty acid shorthand notation into human-readable names.
  Handles common USDA data artifacts and parsing errors.
  """

  @doc """
  Main entry point for formatting fatty acid notations
  """
  def format(notation) when is_binary(notation) do
    notation
    |> normalize_notation()
    |> extract_fatty_acid_info()
    |> generate_human_readable_name()
  end

  def format(_), do: "Unknown Fatty Acid"

  # Step 1: Normalize the notation (fix common parsing errors)
  defp normalize_notation(notation) do
    notation
    |> String.downcase()
    |> String.replace("_", " ")
    |> fix_dropped_digits()
    |> fix_common_typos()
    |> String.trim()
  end

  defp fix_dropped_digits(notation) do
    notation
    # Only apply replacement if the pattern matches
    |> maybe_replace_dropped_digits()
    |> maybe_replace_c_pattern()
  end

  defp maybe_replace_dropped_digits(string) do
    # Check if pattern exists before attempting replacement
    if Regex.match?(~r/\b\d:\d{2}\b/, string) do
      Regex.replace(
        ~r/\b(\d):(\d{2})\b/,
        string,
        fn _, carbon, db ->
          case carbon do
            "1" -> "18:#{db}"
            "2" -> "20:#{db}"
            "3" -> "22:#{db}"
            "4" -> "14:#{db}"
            "5" -> "15:#{db}"
            "6" -> "16:#{db}"
            _ -> "#{carbon}:#{db}"
          end
        end,
        []
      )
    else
      string
    end
  end

  defp maybe_replace_c_pattern(string) do
    if Regex.match?(~r/C\d:\d{2}/i, string) do
      Regex.replace(
        ~r/C(\d):(\d{2})/i,
        string,
        fn _, carbon, db ->
          case carbon do
            "1" -> "C18:#{db}"
            "2" -> "C20:#{db}"
            "3" -> "C22:#{db}"
            "4" -> "C14:#{db}"
            "5" -> "C15:#{db}"
            "6" -> "C16:#{db}"
            _ -> "C#{carbon}:#{db}"
          end
        end,
        []
      )
    else
      string
    end
  end

  # Fix other common typos
  defp fix_common_typos(notation) do
    notation
    |> String.replace("pufa", "PUFA")
    |> String.replace("mufa", "MUFA")
    |> String.replace("sfa", "SFA")
    |> String.replace("omega", "n-")
    |> String.replace("n--", "n-")
  end

  # Step 2: Extract carbon count, double bonds, and type information
  defp extract_fatty_acid_info(notation) do
    # Try to extract carbon and double bonds
    {carbon, double_bonds} =
      case Regex.run(~r/(\d{1,2})[:]\s*(\d{1,2})/, notation) do
        [_, c, db] -> {String.to_integer(c), String.to_integer(db)}
        nil -> {nil, nil}
      end

    # Determine if it's saturated (SFA), monounsaturated (MUFA), or polyunsaturated (PUFA)
    fatty_type =
      cond do
        notation =~ ~r/\bPUFA\b/i or notation =~ ~r/polyunsaturated/i -> :PUFA
        notation =~ ~r/\bMUFA\b/i or notation =~ ~r/monounsaturated/i -> :MUFA
        notation =~ ~r/\bSFA\b/i or notation =~ ~r/saturated/i -> :SFA
        double_bonds == 0 -> :SFA
        double_bonds == 1 -> :MUFA
        double_bonds >= 2 -> :PUFA
        true -> :UNKNOWN
      end

    # Determine omega type (n-3, n-6, n-7, n-9)
    omega_type =
      cond do
        notation =~ ~r/n-3|omega-3/ -> "n-3"
        notation =~ ~r/n-6|omega-6/ -> "n-6"
        notation =~ ~r/n-7|omega-7/ -> "n-7"
        notation =~ ~r/n-9|omega-9/ -> "n-9"
        true -> nil
      end

    %{
      raw: notation,
      carbon: carbon,
      double_bonds: double_bonds,
      type: fatty_type,
      omega: omega_type
    }
  end

  # Step 3: Generate human-readable name
  defp generate_human_readable_name(%{carbon: nil, double_bonds: nil} = info) do
    get_common_name(info.raw)
  end

  defp generate_human_readable_name(%{carbon: c, double_bonds: db} = info)
       when is_integer(c) and is_integer(db) do
    case validate_fatty_acid(c, db) do
      {:error, reason} ->
        corrected = attempt_correction(c, db, info)

        if corrected != info do
          generate_human_readable_name(corrected)
        else
          "⚠️ #{reason}"
        end

      :ok ->
        case info.type do
          :SFA -> format_saturated(c, db)
          :MUFA -> format_monounsaturated(c, db, info.omega)
          :PUFA -> format_polyunsaturated(c, db, info.omega, info.raw)
          _ -> format_general(c, db, info.omega)
        end
    end
  end

  defp generate_human_readable_name(_), do: "Unknown Fatty Acid"

  # Validation
  defp validate_fatty_acid(carbon, double_bonds) do
    cond do
      carbon < 4 ->
        {:error, "C#{carbon} is too short for a fatty acid (minimum 4 carbons)"}

      carbon > 30 ->
        {:error, "C#{carbon} exceeds typical fatty acid chain length"}

      double_bonds > max_double_bonds(carbon) ->
        {:error,
         "C#{carbon} cannot have #{double_bonds} double bonds (maximum #{max_double_bonds(carbon)})"}

      true ->
        :ok
    end
  end

  defp max_double_bonds(carbon) do
    cond do
      carbon <= 4 -> 0
      carbon <= 6 -> 1
      carbon <= 10 -> 2
      carbon <= 14 -> 3
      carbon <= 18 -> 4
      carbon <= 22 -> 6
      true -> floor(carbon / 3)
    end
  end

  # Attempt to correct invalid fatty acids
  defp attempt_correction(carbon, double_bonds, info) do
    cond do
      carbon == 2 and double_bonds == 4 ->
        %{info | carbon: 20, double_bonds: 4, raw: String.replace(info.raw, "2:4", "20:4")}

      carbon == 2 and double_bonds == 5 ->
        %{info | carbon: 20, double_bonds: 5, raw: String.replace(info.raw, "2:5", "20:5")}

      carbon == 2 and double_bonds == 6 ->
        %{info | carbon: 22, double_bonds: 6, raw: String.replace(info.raw, "2:6", "22:6")}

      carbon == 1 and double_bonds == 2 ->
        %{info | carbon: 18, double_bonds: 2, raw: String.replace(info.raw, "1:2", "18:2")}

      carbon == 1 and double_bonds == 3 ->
        %{info | carbon: 18, double_bonds: 3, raw: String.replace(info.raw, "1:3", "18:3")}

      carbon == 3 and double_bonds == 4 ->
        %{info | carbon: 22, double_bonds: 4, raw: String.replace(info.raw, "3:4", "22:4")}

      true ->
        info
    end
  end

  # Format saturated fatty acids (SFA)
  defp format_saturated(carbon, _double_bonds) do
    case carbon do
      4 -> "Butyric Acid (C4:0)"
      6 -> "Caproic Acid (C6:0)"
      8 -> "Caprylic Acid (C8:0)"
      10 -> "Capric Acid (C10:0)"
      12 -> "Lauric Acid (C12:0)"
      14 -> "Myristic Acid (C14:0)"
      15 -> "Pentadecanoic Acid (C15:0)"
      16 -> "Palmitic Acid (C16:0)"
      17 -> "Margaric Acid (C17:0)"
      18 -> "Stearic Acid (C18:0)"
      20 -> "Arachidic Acid (C20:0)"
      22 -> "Behenic Acid (C22:0)"
      24 -> "Lignoceric Acid (C24:0)"
      _ -> "C#{carbon}:0 Saturated Fatty Acid"
    end
  end

  # Format monounsaturated fatty acids (MUFA)
  defp format_monounsaturated(carbon, double_bonds, omega) do
    cond do
      carbon == 14 and double_bonds == 1 ->
        "Myristoleic Acid (C14:1)"

      carbon == 16 and double_bonds == 1 ->
        "Palmitoleic Acid (C16:1, Omega-7)"

      carbon == 17 and double_bonds == 1 ->
        "Heptadecenoic Acid (C17:1)"

      carbon == 18 and double_bonds == 1 ->
        if omega == "n-7" do
          "Vaccenic Acid (C18:1, Omega-7)"
        else
          "Oleic Acid (C18:1, Omega-9)"
        end

      carbon == 20 and double_bonds == 1 ->
        "Gadoleic Acid (C20:1, Omega-9)"

      carbon == 22 and double_bonds == 1 ->
        "Erucic Acid (C22:1, Omega-9)"

      carbon == 24 and double_bonds == 1 ->
        "Nervonic Acid (C24:1, Omega-9)"

      true ->
        "C#{carbon}:#{double_bonds} Monounsaturated Fatty Acid"
    end
  end

  # Format polyunsaturated fatty acids (PUFA)
  defp format_polyunsaturated(carbon, double_bonds, omega, _raw) do
    case omega do
      "n-3" -> format_omega_3(carbon, double_bonds)
      "n-6" -> format_omega_6(carbon, double_bonds)
      "n-7" -> format_omega_7(carbon, double_bonds)
      "n-9" -> format_omega_9(carbon, double_bonds)
      nil -> format_general_pufa(carbon, double_bonds)
    end
  end

  defp format_omega_3(carbon, double_bonds) do
    case {carbon, double_bonds} do
      {18, 3} -> "Alpha-Linolenic Acid (ALA, Omega-3)"
      {18, 4} -> "Stearidonic Acid (Omega-3)"
      {20, 4} -> "Eicosatetraenoic Acid (ETA, Omega-3)"
      {20, 5} -> "Eicosapentaenoic Acid (EPA, Omega-3)"
      {22, 5} -> "Docosapentaenoic Acid (DPA, Omega-3)"
      {22, 6} -> "Docosahexaenoic Acid (DHA, Omega-3)"
      _ -> "C#{carbon}:#{double_bonds} (Omega-3) Polyunsaturated Fatty Acid"
    end
  end

  defp format_omega_6(carbon, double_bonds) do
    case {carbon, double_bonds} do
      {18, 2} -> "Linoleic Acid (LA, Omega-6)"
      {18, 3} -> "Gamma-Linolenic Acid (GLA, Omega-6)"
      {20, 2} -> "Eicosadienoic Acid (Omega-6)"
      {20, 3} -> "Dihomo-Gamma-Linolenic Acid (DGLA, Omega-6)"
      {20, 4} -> "Arachidonic Acid (AA, Omega-6)"
      {22, 4} -> "Adrenic Acid (Omega-6)"
      {22, 5} -> "Docosapentaenoic Acid (Omega-6)"
      _ -> "C#{carbon}:#{double_bonds} (Omega-6) Polyunsaturated Fatty Acid"
    end
  end

  defp format_omega_7(carbon, double_bonds) do
    case {carbon, double_bonds} do
      {16, 1} -> "Palmitoleic Acid (Omega-7)"
      {18, 1} -> "Vaccenic Acid (Omega-7)"
      _ -> "C#{carbon}:#{double_bonds} (Omega-7) Fatty Acid"
    end
  end

  defp format_omega_9(carbon, double_bonds) do
    case {carbon, double_bonds} do
      {14, 1} -> "Myristoleic Acid (Omega-9)"
      {16, 1} -> "Palmitoleic Acid (Omega-9)"
      {18, 1} -> "Oleic Acid (Omega-9)"
      {20, 1} -> "Gadoleic Acid (Omega-9)"
      {20, 3} -> "Mead Acid (Omega-9)"
      {22, 1} -> "Erucic Acid (Omega-9)"
      {24, 1} -> "Nervonic Acid (Omega-9)"
      _ -> "C#{carbon}:#{double_bonds} (Omega-9) Fatty Acid"
    end
  end

  defp format_general_pufa(carbon, double_bonds) do
    case {carbon, double_bonds} do
      {18, 2} -> "Linoleic Acid"
      {18, 3} -> "Linolenic Acid"
      {20, 3} -> "Eicosatrienoic Acid"
      {20, 4} -> "Arachidonic Acid"
      {20, 5} -> "Eicosapentaenoic Acid (EPA)"
      {22, 3} -> "Docosatrienoic Acid"
      {22, 4} -> "Docosatetraenoic Acid"
      {22, 5} -> "Docosapentaenoic Acid"
      {22, 6} -> "Docosahexaenoic Acid (DHA)"
      _ -> "C#{carbon}:#{double_bonds} Polyunsaturated Fatty Acid"
    end
  end

  defp format_general(carbon, double_bonds, omega) do
    omega_str = if omega, do: " (#{omega})", else: ""
    "C#{carbon}:#{double_bonds}#{omega_str} Fatty Acid"
  end

  # Fallback for common names
  defp get_common_name(raw) do
    raw_lower = String.downcase(raw)

    cond do
      raw_lower =~ ~r/dha/ -> "Docosahexaenoic Acid (DHA, Omega-3)"
      raw_lower =~ ~r/epa/ -> "Eicosapentaenoic Acid (EPA, Omega-3)"
      raw_lower =~ ~r/ala/ -> "Alpha-Linolenic Acid (ALA, Omega-3)"
      raw_lower =~ ~r/la\b/ -> "Linoleic Acid (LA, Omega-6)"
      raw_lower =~ ~r/gla/ -> "Gamma-Linolenic Acid (GLA, Omega-6)"
      raw_lower =~ ~r/aa\b/ -> "Arachidonic Acid (AA, Omega-6)"
      raw_lower =~ ~r/oleic/ -> "Oleic Acid (Omega-9)"
      true -> raw
    end
  end
end
