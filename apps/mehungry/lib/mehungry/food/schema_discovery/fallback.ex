# apps/mehungry/lib/mehungry/food/schema_discovery/fallback.ex
defmodule Mehungry.Food.SchemaDiscovery.Fallback do
  @moduledoc """
  Lightweight, embeddings-free schema discovery.

  A thin reshaping of `PureEx.analyze/0` into a flat `fields`/`coverage`/
  `recommendations` summary — it reuses `PureEx`'s single regex set rather than
  maintaining its own, and (like `Coverage`) computes coverage over the **union**
  of matched ingredients and only proposes migrations for dimensions the parser
  does not already capture.
  """

  alias Mehungry.Food.SchemaDiscovery.PureEx

  @doc """
  Discover schema fields using pure Elixir patterns. Works even when embeddings
  are disabled (nothing here needs them).
  """
  @spec discover() :: %{
          fields: [map()],
          coverage: float(),
          recommendations: [String.t()]
        }
  def discover do
    analysis = PureEx.analyze()
    total = analysis.total_ingredients

    fields =
      Enum.map(analysis.recommendations, fn r ->
        %{
          field: r.field,
          count: length(r.matched_ids),
          coverage: r.coverage,
          existing_column: r.existing_column,
          new_column?: r.new_column?,
          priority: priority_label(r.coverage),
          migration: migration_sql(r)
        }
      end)

    coverage =
      analysis.recommendations
      |> Enum.flat_map(& &1.matched_ids)
      |> MapSet.new()
      |> MapSet.size()
      |> then(fn covered -> if total > 0, do: covered / total, else: 0.0 end)

    %{
      fields: fields,
      coverage: coverage,
      recommendations: generate_recommendations(fields)
    }
  end

  defp priority_label(coverage) do
    cond do
      coverage >= 0.5 -> "HIGH"
      coverage >= 0.25 -> "MEDIUM"
      coverage >= 0.1 -> "LOW"
      true -> "MINIMAL"
    end
  end

  # Only dimensions the parser does not already capture warrant a new column.
  defp migration_sql(%{new_column?: false}), do: nil

  defp migration_sql(%{field: field}) do
    """
    ALTER TABLE ingredient_parsed_foods ADD COLUMN #{field} TEXT;
    CREATE INDEX idx_ingredient_parsed_foods_#{field} ON ingredient_parsed_foods(#{field});
    """
  end

  defp generate_recommendations(fields) do
    needed =
      fields
      |> Enum.filter(fn f -> f.new_column? and f.coverage > 0.05 end)
      |> Enum.map(fn f ->
        "Add #{f.field} - #{f.priority} priority (#{round(f.coverage * 100)}% of ingredients)"
      end)

    if Enum.empty?(needed) do
      ["No un-captured patterns above threshold. Parser already covers the mined dimensions."]
    else
      needed
    end
  end
end
