# apps/mehungry/lib/mehungry/food/schema_discovery/pure_ex.ex
defmodule Mehungry.Food.SchemaDiscovery.PureEx do
  @moduledoc """
  Pure Elixir pattern discovery from USDA ingredient names.
  No ML dependencies - uses regex and string operations.

  This is the single source of truth for the mined dimensions: each entry in
  `@patterns` names a dimension, its `\\b`-anchored regex, the match `mode`, and
  the `ingredient_parsed_foods` column that already captures it (`nil` when the
  dimension is not yet captured by the deterministic parser). `Fallback` and
  `Coverage` build on this map rather than re-deriving their own regexes.

  Coverage for a dimension is the fraction of **distinct ingredients** whose name
  matches it (via `matched_ids`), so downstream union math (`Coverage`) never
  double-counts a name that matches several dimensions.
  """

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.Repo

  @type pattern_result :: %{
          value: String.t(),
          count: non_neg_integer(),
          examples: [non_neg_integer()]
        }

  @type recommendation :: %{
          field: atom(),
          total_occurrences: non_neg_integer(),
          unique_values: non_neg_integer(),
          coverage: float(),
          matched_ids: [non_neg_integer()],
          existing_column: atom() | nil,
          new_column?: boolean(),
          top_values: [pattern_result()],
          priority: String.t()
        }

  # dimension => %{regex, mode, column}
  #   mode :capture -> Regex.run/2, keep capture group 1 verbatim
  #   mode :scan    -> Regex.scan/2, downcased + de-duped per ingredient
  #   column        -> existing ingredient_parsed_foods column, or nil if the
  #                    deterministic parser does not yet capture this dimension
  @patterns [
    trimmed_to: %{
      regex: ~r/trimmed to ([\d\/"]+ inch|\d+"?)/i,
      mode: :capture,
      column: :fat
    },
    grade: %{
      regex: ~r/\b(choice|select|prime|standard|cutter|canner)\b/i,
      mode: :scan,
      column: :grade
    },
    cut_type: %{
      regex:
        ~r/\b(boneless|bone-in|with bone|skinless|with skin|lip-on|whole|half|quarter|chunk|steak|roast|chop|ground|filet)\b/i,
      mode: :scan,
      # also surfaces in dismemberment/portion
      column: :bone_state
    },
    preparation: %{
      regex:
        ~r/\b(raw|cooked|roasted|grilled|fried|baked|steamed|boiled|sautéed|poached|broiled|smoked|cured|dried|frozen|canned)\b/i,
      mode: :scan,
      column: :processing
    },
    variety: %{
      regex:
        ~r/\b(honeycrisp|gala|fuji|granny smith|russet|yukon|red delicious|golden delicious|cameo|empire|mcintosh|braeburn|pink lady|hass|fuertes|reed|navel|valencia|seedless|japanese|english|roma|vine-ripened)\b/i,
      mode: :scan,
      column: nil
    },
    maturity: %{
      regex: ~r/\b(baby|mature|young|old|spring|winter|unripe|ripe|aged|new crop|harvest)\b/i,
      mode: :scan,
      column: :harvest_stage
    },
    plant_part: %{
      regex:
        ~r/\b(flesh|skin|peel|core|stem|leaf|root|bulb|clove|seed|pit|rind|zest|crown|heart|spear|floret|stalk|rib|tip|crown)\b/i,
      mode: :scan,
      column: :part
    },
    size: %{
      regex:
        ~r/\b(large|medium|small|extra-large|jumbo|mini|giant|petite|extra small|colossal|king|queen)\b/i,
      mode: :scan,
      column: nil
    },
    origin: %{
      regex:
        ~r/\b(atlantic|pacific|wild|cultivated|farm-raised|ocean|freshwater|imported|domestic|local|organic|conventional)\b/i,
      mode: :scan,
      column: nil
    },
    packaging: %{
      regex:
        ~r/\b(whole|piece|loaf|stick|tub|bottle|can|jar|bag|box|carton|tray|wrap|vacuum-packed|frozen|fresh|dried)\b/i,
      mode: :scan,
      column: :packaging
    }
  ]

  @min_values 5

  @doc "The dimension → config map used by the whole subsystem."
  @spec patterns() :: keyword(map())
  def patterns, do: @patterns

  @doc """
  Analyze all ingredients and discover patterns.
  """
  @spec analyze() :: %{
          total_ingredients: non_neg_integer(),
          patterns: map(),
          recommendations: [recommendation()]
        }
  def analyze do
    ingredients = get_ingredients()
    total = length(ingredients)

    fields =
      Enum.map(@patterns, fn {dimension, config} ->
        pairs = extract(ingredients, config)
        values = group_patterns(pairs)
        matched_ids = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
        {dimension, %{values: values, matched_ids: matched_ids, column: config.column}}
      end)
      |> Enum.filter(fn {_dimension, %{values: values}} -> length(values) >= @min_values end)

    %{
      total_ingredients: total,
      patterns: Map.new(fields, fn {dimension, %{values: values}} -> {dimension, values} end),
      recommendations: build_recommendations(fields, total)
    }
  end

  defp get_ingredients do
    Repo.all(
      from i in Ingredient,
        select: [:id, :name],
        where: not is_nil(i.name) and i.name != ""
    )
  end

  # Generic extractors keyed by mode -----------------------------------------

  defp extract(ingredients, %{regex: regex, mode: :capture}) do
    Enum.flat_map(ingredients, fn i ->
      case Regex.run(regex, i.name) do
        [_full, captured] -> [{i.id, captured}]
        _ -> []
      end
    end)
  end

  defp extract(ingredients, %{regex: regex, mode: :scan}) do
    Enum.flat_map(ingredients, fn i ->
      Regex.scan(regex, i.name)
      |> List.flatten()
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()
      |> Enum.map(fn value -> {i.id, value} end)
    end)
  end

  defp group_patterns(items) do
    items
    |> Enum.group_by(fn {_id, value} -> value end)
    |> Enum.map(fn {value, occurrences} ->
      %{
        value: value,
        count: length(occurrences),
        examples: Enum.take(occurrences, 5) |> Enum.map(fn {id, _} -> id end)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp build_recommendations(fields, total) do
    fields
    |> Enum.map(fn {dimension, %{values: values, matched_ids: matched_ids, column: column}} ->
      total_occurrences = Enum.sum(Enum.map(values, & &1.count))
      coverage = safe_div(length(matched_ids), total)

      %{
        field: dimension,
        total_occurrences: total_occurrences,
        unique_values: length(values),
        coverage: coverage,
        matched_ids: matched_ids,
        existing_column: column,
        new_column?: is_nil(column),
        top_values: Enum.take(values, 5),
        priority: priority_label(coverage)
      }
    end)
    |> Enum.sort_by(& &1.coverage, :desc)
  end

  defp safe_div(_numerator, 0), do: 0.0
  defp safe_div(numerator, denominator), do: numerator / denominator

  defp priority_label(coverage) do
    cond do
      coverage >= 0.5 -> "HIGH - Add immediately"
      coverage >= 0.25 -> "MEDIUM - Consider adding"
      coverage >= 0.1 -> "LOW - Optional"
      true -> "MINIMAL - Skip for now"
    end
  end
end
