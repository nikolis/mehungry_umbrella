defmodule MehungryWeb.NutrientMapper do
  use GenServer
  require Logger

  def init(init_arg), do: {:ok, init_arg}

  def get_nutrient_name(nutrient_id, fallback_name \\ nil) do
    name =
      if fallback_name && fallback_name != "", do: fallback_name, else: to_string(nutrient_id)

    humanize_nutrient_name(name)
  end

  def get_all_mappings, do: %{}

  def status, do: %{loaded_count: 1}

  def humanize_nutrient_name(name) when is_binary(name) do
    name
    |> String.replace("_", " ")
    |> String.trim()
    |> apply_fatty_acid_mappings()
    |> apply_vitamin_mappings()
    |> apply_mineral_mappings()
    |> capitalize_properly()
  end

  def humanize_nutrient_name(_), do: "Unknown Nutrient"

  # Complete rewritten fatty acid mapping
  defp apply_fatty_acid_mappings(original_name) do
    name = String.downcase(original_name)

    # First, handle exact known common names (highest priority)
    cond do
      # =========================================================================
      # EXACT COMMON NAME MATCHES (Hardcoded for speed)
      # =========================================================================
      name == "dha" or name == "docosahexaenoic acid" ->
        "Docosahexaenoic Acid (DHA, Omega-3)"

      name == "epa" or name == "eicosapentaenoic acid" ->
        "Eicosapentaenoic Acid (EPA, Omega-3)"

      name == "ala" or name == "alpha-linolenic acid" ->
        "Alpha-Linolenic Acid (ALA, Omega-3)"

      name == "gla" or name == "gamma-linolenic acid" ->
        "Gamma-Linolenic Acid (GLA, Omega-6)"

      name == "la" or name == "linoleic acid" ->
        "Linoleic Acid (Omega-6)"

      name == "aa" or name == "arachidonic acid" ->
        "Arachidonic Acid (AA, Omega-6)"

      name == "oleic acid" ->
        "Oleic Acid (Omega-9)"

      name == "palmitic acid" ->
        "Palmitic Acid (C16:0)"

      name == "stearic acid" ->
        "Stearic Acid (C18:0)"

      name == "lauric acid" ->
        "Lauric Acid (C12:0)"

      name == "myristic acid" ->
        "Myristic Acid (C14:0)"

      name == "capric acid" ->
        "Capric Acid (C10:0)"

      name == "caprylic acid" ->
        "Caprylic Acid (C8:0)"

      name == "caproic acid" ->
        "Caproic Acid (C6:0)"

      name == "butyric acid" ->
        "Butyric Acid (C4:0)"

      # =========================================================================
      # PATTERN-BASED MATCHING (Handles almost any shorthand notation)
      # =========================================================================

      # -------------------------------------------------------------------------
      # OMEGA-3 (n-3) FAMILY
      # -------------------------------------------------------------------------

      # DHA pattern: 22:6
      Regex.match?(~r/22[:]\s*6/, name) or Regex.match?(~r/22[:]\s*6/, name) ->
        "Docosahexaenoic Acid (DHA, Omega-3)"

      # EPA pattern: 20:5
      Regex.match?(~r/20[:]\s*5/, name) ->
        "Eicosapentaenoic Acid (EPA, Omega-3)"

      # DPA pattern: 22:5
      Regex.match?(~r/22[:]\s*5/, name) ->
        "Docosapentaenoic Acid (DPA, Omega-3)"

      # ETA pattern: 20:4 n-3
      Regex.match?(~r/20[:]\s*4.*n-3/, name) ->
        "Eicosatetraenoic Acid (ETA, Omega-3)"

      # HPA pattern: 18:4
      Regex.match?(~r/18[:]\s*4/, name) ->
        "Stearidonic Acid (Omega-3)"

      # ALA pattern: 18:3 n-3
      Regex.match?(~r/18[:]\s*3.*n-3/, name) ->
        "Alpha-Linolenic Acid (ALA, Omega-3)"

      # 16:3 n-3
      Regex.match?(~r/16[:]\s*3.*n-3/, name) ->
        "Hexadecatrienoic Acid (Omega-3)"

      # -------------------------------------------------------------------------
      # OMEGA-6 (n-6) FAMILY
      # -------------------------------------------------------------------------

      # Arachidonic: 20:4 n-6
      Regex.match?(~r/20[:]\s*4.*n-6/, name) ->
        "Arachidonic Acid (AA, Omega-6)"

      # DGLA: 20:3 n-6
      Regex.match?(~r/20[:]\s*3.*n-6/, name) ->
        "Dihomo-gamma-linolenic Acid (DGLA, Omega-6)"

      # GLA: 18:3 n-6
      Regex.match?(~r/18[:]\s*3.*n-6/, name) ->
        "Gamma-Linolenic Acid (GLA, Omega-6)"

      # Linoleic: 18:2 n-6 or just 18:2
      Regex.match?(~r/18[:]\s*2/, name) ->
        "Linoleic Acid (Omega-6)"

      # 20:2 n-6
      Regex.match?(~r/20[:]\s*2/, name) ->
        "Eicosadienoic Acid (Omega-6)"

      # 22:4 n-6
      Regex.match?(~r/22[:]\s*4.*n-6/, name) ->
        "Adrenic Acid (Omega-6)"

      # 22:5 n-6
      Regex.match?(~r/22[:]\s*5.*n-6/, name) ->
        "Docosapentaenoic Acid (Omega-6)"

      # 24:4 n-6
      Regex.match?(~r/24[:]\s*4.*n-6/, name) ->
        "Tetracosatetraenoic Acid (Omega-6)"

      # -------------------------------------------------------------------------
      # OMEGA-7 (n-7) FAMILY
      # -------------------------------------------------------------------------

      # Palmitoleic: 16:1 n-7 or just 16:1
      Regex.match?(~r/16[:]\s*1/, name) ->
        "Palmitoleic Acid (Omega-7)"

      # Vaccenic: 18:1 n-7
      Regex.match?(~r/18[:]\s*1.*n-7/, name) ->
        "Vaccenic Acid (Omega-7)"

      # 20:1 n-7
      Regex.match?(~r/20[:]\s*1.*n-7/, name) ->
        "Paullinic Acid (Omega-7)"

      # -------------------------------------------------------------------------
      # OMEGA-9 (n-9) FAMILY
      # -------------------------------------------------------------------------

      # Erucic: 22:1 n-9
      Regex.match?(~r/22[:]\s*1/, name) ->
        "Erucic Acid (Omega-9)"

      # Gadoleic: 20:1 n-9
      Regex.match?(~r/20[:]\s*1/, name) ->
        "Gadoleic Acid (Omega-9)"

      # Oleic: 18:1 n-9 or just 18:1
      Regex.match?(~r/18[:]\s*1/, name) ->
        "Oleic Acid (Omega-9)"

      # 16:1 n-9
      Regex.match?(~r/16[:]\s*1.*n-9/, name) ->
        "Sapienic Acid (Omega-9)"

      # 14:1 n-9 (for MUFA 14:1)
      Regex.match?(~r/14[:]\s*1/, name) ->
        "Myristoleic Acid (Omega-9)"

      # 24:1 n-9
      Regex.match?(~r/24[:]\s*1/, name) ->
        "Nervonic Acid (Omega-9)"

      # -------------------------------------------------------------------------
      # SATURATED FATTY ACIDS (SFA) - Chain length
      # -------------------------------------------------------------------------

      # Capture any X:0 pattern (saturated)
      Regex.match?(~r/(\d+)[:]\s*0/, name) ->
        case Regex.run(~r/(\d+)[:]\s*0/, name) do
          [_, carbon_count] ->
            carbon = String.to_integer(carbon_count)
            format_saturated_fatty_acid(carbon)

          _ ->
            "Saturated Fatty Acid"
        end

      # -------------------------------------------------------------------------
      # MONOUNSATURATED (MUFA) - Generic X:1 pattern
      # -------------------------------------------------------------------------

      # Capture any X:1 pattern (monounsaturated) not already caught
      Regex.match?(~r/(\d+)[:]\s*1/, name) ->
        case Regex.run(~r/(\d+)[:]\s*1/, name) do
          [_, carbon_count] ->
            carbon = String.to_integer(carbon_count)
            format_monounsaturated_fatty_acid(carbon)

          _ ->
            "Monounsaturated Fatty Acid"
        end

      # -------------------------------------------------------------------------
      # POLYUNSATURATED (PUFA) - Generic X:Y pattern with Y>=2
      # -------------------------------------------------------------------------

      # Capture any X:Y pattern with Y>=2 (diunsaturated or more)
      Regex.match?(~r/(\d+)[:]\s*([2-9])/, name) ->
        case Regex.run(~r/(\d+)[:]\s*([2-9])/, name) do
          [_, carbon_count, double_bonds] ->
            carbon = String.to_integer(carbon_count)
            bonds = String.to_integer(double_bonds)
            format_polyunsaturated_fatty_acid(carbon, bonds, name)

          _ ->
            "Polyunsaturated Fatty Acid"
        end

      # -------------------------------------------------------------------------
      # TRANS FATTY ACIDS (TFA)
      # -------------------------------------------------------------------------

      # TFA 18:3 t (tri-trans)
      Regex.match?(~r/18[:]\s*3.*t/, name) ->
        "Trans-Octadecatrienoic Acid"

      # TFA 18:2 t (di-trans)
      Regex.match?(~r/18[:]\s*2.*t/, name) ->
        "Trans-Linoleic Acid"

      # TFA 18:1 t (trans-oleic / elaidic)
      Regex.match?(~r/18[:]\s*1.*t/, name) ->
        "Elaidic Acid (Trans-18:1)"

      # Any trans fatty acid
      String.contains?(name, "trans") or Regex.match?(~r/\bt\b/, name) ->
        "Trans Fatty Acid"

      # -------------------------------------------------------------------------
      # GENERAL CATEGORIES (Lowest priority - catch-all)
      # -------------------------------------------------------------------------

      # PUFA general
      Regex.match?(~r/\bpufa\b/i, name) or
          (String.contains?(name, "polyunsaturated") and not Regex.match?(~r/\d+[:]\s*\d+/, name)) ->
        "Polyunsaturated Fat"

      # MUFA general
      Regex.match?(~r/\bmufa\b/i, name) or
          (String.contains?(name, "monounsaturated") and not Regex.match?(~r/\d+[:]\s*\d+/, name)) ->
        "Monounsaturated Fat"

      # SFA general
      Regex.match?(~r/\bsfa\b/i, name) or
          (String.contains?(name, "saturated") and not Regex.match?(~r/\d+[:]\s*\d+/, name)) ->
        "Saturated Fat"

      # =========================================================================
      # FALLBACK
      # =========================================================================

      true ->
        original_name
    end
  end

  # Helper: Format saturated fatty acids by carbon chain length
  defp format_saturated_fatty_acid(carbon) do
    case carbon do
      4 -> "Butyric Acid (C4:0)"
      5 -> "Valeric Acid (C5:0)"
      6 -> "Caproic Acid (C6:0)"
      7 -> "Enanthic Acid (C7:0)"
      8 -> "Caprylic Acid (C8:0)"
      9 -> "Nonanoic Acid (C9:0)"
      10 -> "Capric Acid (C10:0)"
      11 -> "Undecanoic Acid (C11:0)"
      12 -> "Lauric Acid (C12:0)"
      13 -> "Tridecanoic Acid (C13:0)"
      14 -> "Myristic Acid (C14:0)"
      15 -> "Pentadecanoic Acid (C15:0)"
      16 -> "Palmitic Acid (C16:0)"
      17 -> "Margaric Acid (C17:0)"
      18 -> "Stearic Acid (C18:0)"
      19 -> "Nonadecanoic Acid (C19:0)"
      20 -> "Arachidic Acid (C20:0)"
      21 -> "Heneicosanoic Acid (C21:0)"
      22 -> "Behenic Acid (C22:0)"
      23 -> "Tricosanoic Acid (C23:0)"
      24 -> "Lignoceric Acid (C24:0)"
      _ -> "C#{carbon}:0 Saturated Fatty Acid"
    end
  end

  # Helper: Format monounsaturated fatty acids
  defp format_monounsaturated_fatty_acid(carbon) do
    case carbon do
      10 -> "Caproleic Acid (C10:1)"
      12 -> "Lauroleic Acid (C12:1)"
      14 -> "Myristoleic Acid (C14:1)"
      16 -> "Palmitoleic Acid (C16:1, Omega-7)"
      17 -> "Heptadecenoic Acid (C17:1)"
      18 -> "Oleic Acid (C18:1, Omega-9)"
      20 -> "Gadoleic Acid (C20:1, Omega-9)"
      22 -> "Erucic Acid (C22:1, Omega-9)"
      24 -> "Nervonic Acid (C24:1, Omega-9)"
      _ -> "C#{carbon}:1 Monounsaturated Fatty Acid"
    end
  end

  # Helper: Format polyunsaturated fatty acids
  defp format_polyunsaturated_fatty_acid(carbon, double_bonds, original_name) do
    # Check for Omega-3/6/7/9 indicators in the original name
    name_lower = String.downcase(original_name)

    cond do
      String.contains?(name_lower, "n-3") or String.contains?(name_lower, "omega-3") ->
        get_omega3_name(carbon, double_bonds)

      String.contains?(name_lower, "n-6") or String.contains?(name_lower, "omega-6") ->
        get_omega6_name(carbon, double_bonds)

      String.contains?(name_lower, "n-9") or String.contains?(name_lower, "omega-9") ->
        get_omega9_name(carbon, double_bonds)

      true ->
        # Default by carbon/double bond pattern
        get_general_pufa_name(carbon, double_bonds)
    end
  end

  defp get_omega3_name(carbon, double_bonds) do
    cond do
      carbon == 18 and double_bonds == 3 -> "Alpha-Linolenic Acid (ALA, Omega-3)"
      carbon == 18 and double_bonds == 4 -> "Stearidonic Acid (Omega-3)"
      carbon == 20 and double_bonds == 4 -> "Eicosatetraenoic Acid (ETA, Omega-3)"
      carbon == 20 and double_bonds == 5 -> "Eicosapentaenoic Acid (EPA, Omega-3)"
      carbon == 22 and double_bonds == 5 -> "Docosapentaenoic Acid (DPA, Omega-3)"
      carbon == 22 and double_bonds == 6 -> "Docosahexaenoic Acid (DHA, Omega-3)"
      carbon == 24 and double_bonds == 6 -> "Tetracosahexaenoic Acid (Omega-3)"
      true -> "C#{carbon}:#{double_bonds} (Omega-3)"
    end
  end

  defp get_omega6_name(carbon, double_bonds) do
    cond do
      carbon == 18 and double_bonds == 2 -> "Linoleic Acid (Omega-6)"
      carbon == 18 and double_bonds == 3 -> "Gamma-Linolenic Acid (GLA, Omega-6)"
      carbon == 20 and double_bonds == 2 -> "Eicosadienoic Acid (Omega-6)"
      carbon == 20 and double_bonds == 3 -> "Dihomo-gamma-linolenic Acid (DGLA, Omega-6)"
      carbon == 20 and double_bonds == 4 -> "Arachidonic Acid (AA, Omega-6)"
      carbon == 22 and double_bonds == 4 -> "Adrenic Acid (Omega-6)"
      carbon == 22 and double_bonds == 5 -> "Docosapentaenoic Acid (Omega-6)"
      true -> "C#{carbon}:#{double_bonds} (Omega-6)"
    end
  end

  defp get_omega9_name(carbon, double_bonds) do
    cond do
      carbon == 18 and double_bonds == 1 -> "Oleic Acid (Omega-9)"
      carbon == 20 and double_bonds == 1 -> "Gadoleic Acid (Omega-9)"
      carbon == 20 and double_bonds == 3 -> "Mead Acid (Omega-9)"
      carbon == 22 and double_bonds == 1 -> "Erucic Acid (Omega-9)"
      carbon == 24 and double_bonds == 1 -> "Nervonic Acid (Omega-9)"
      true -> "C#{carbon}:#{double_bonds} (Omega-9)"
    end
  end

  defp get_general_pufa_name(carbon, double_bonds) do
    cond do
      carbon == 18 and double_bonds == 2 -> "Linoleic Acid"
      carbon == 18 and double_bonds == 3 -> "Linolenic Acid"
      carbon == 20 and double_bonds == 4 -> "Arachidonic Acid"
      carbon == 20 and double_bonds == 5 -> "Eicosapentaenoic Acid (EPA)"
      carbon == 22 and double_bonds == 6 -> "Docosahexaenoic Acid (DHA)"
      true -> "C#{carbon}:#{double_bonds} Polyunsaturated Fatty Acid"
    end
  end

  defp apply_vitamin_mappings(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, "vitamin a") and String.contains?(name_lower, "rae") ->
        "Vitamin A (Retinol Activity Equivalents)"

      String.contains?(name_lower, "vitamin a") ->
        "Vitamin A"

      String.contains?(name_lower, "vitamin d") ->
        "Vitamin D"

      String.contains?(name_lower, "vitamin b-12") or String.contains?(name_lower, "vitamin b12") ->
        "Vitamin B12"

      String.contains?(name_lower, "vitamin b-6") or String.contains?(name_lower, "vitamin b6") ->
        "Vitamin B6"

      String.contains?(name_lower, "vitamin c") ->
        "Vitamin C"

      String.contains?(name_lower, "vitamin e") ->
        "Vitamin E"

      String.contains?(name_lower, "vitamin k") ->
        "Vitamin K"

      true ->
        name
    end
  end

  defp apply_mineral_mappings(name) do
    cond do
      name == "Ca" -> "Calcium"
      name == "Fe" -> "Iron"
      name == "K" -> "Potassium"
      name == "Na" -> "Sodium"
      name == "Mg" -> "Magnesium"
      name == "Zn" -> "Zinc"
      name == "Cu" -> "Copper"
      name == "Mn" -> "Manganese"
      name == "Se" -> "Selenium"
      name == "P" -> "Phosphorus"
      true -> name
    end
  end

  defp capitalize_properly(name) do
    name
    |> String.split(" ")
    |> Enum.map(fn word ->
      case String.downcase(word) do
        "and" ->
          "and"

        "of" ->
          "of"

        "in" ->
          "in"

        "to" ->
          "to"

        "for" ->
          "for"

        "with" ->
          "with"

        "by" ->
          "by"

        "a" ->
          "a"

        "an" ->
          "an"

        "the" ->
          "the"

        other ->
          # Don't capitalize acronyms like DHA, EPA, ALA
          if String.upcase(other) == other and String.length(other) <= 4 do
            other
          else
            String.capitalize(other)
          end
      end
    end)
    |> Enum.join(" ")
  end
end
