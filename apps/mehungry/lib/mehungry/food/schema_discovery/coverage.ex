# apps/mehungry/lib/mehungry/food/schema_discovery/coverage.ex
defmodule Mehungry.Food.SchemaDiscovery.Coverage do
  @moduledoc """
  Turns `PureEx` dimension analysis into an actionable schema-coverage report:
  the minimal set of mined dimensions that together cover `target` of all
  ingredients, and `ADD COLUMN` migrations **only for dimensions the parser does
  not already capture** (`new_column? == true`).

  Coverage is computed over the **union** of matched ingredient ids, not a sum of
  per-dimension fractions — one ingredient name matches many dimensions, so
  summing overshoots. `parse_fill_rate/0` is a separate, unrelated metric (how
  many ingredients have a linked `canonical_food`), reported alongside but never
  conflated with dimension coverage.
  """

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.IngredientParsedFood
  alias Mehungry.Food.SchemaDiscovery.PureEx
  alias Mehungry.Repo

  @doc """
  Recommend the minimal dimension set to reach `target` coverage (default 95%).
  """
  @spec recommend(float()) :: %{
          total_ingredients: non_neg_integer(),
          parse_fill_rate: float(),
          current_coverage: float(),
          projected_coverage: float(),
          fields_needed: [map()],
          migration_sql: [String.t()],
          summary: String.t()
        }
  def recommend(target \\ 0.95) do
    total = Repo.aggregate(Ingredient, :count)
    analysis = PureEx.analyze()

    fields =
      analysis.recommendations
      |> Enum.filter(&(&1.coverage > 0))
      |> Enum.sort_by(& &1.coverage, :desc)

    {needed, projected} = find_minimal_set(fields, total, target)

    %{
      total_ingredients: total,
      parse_fill_rate: parse_fill_rate(),
      # coverage already reachable from dimensions the parser captures
      current_coverage: coverage_of(covered_ids(fields, &(not &1.new_column?)), total),
      projected_coverage: projected,
      fields_needed: needed,
      migration_sql: generate_migration(needed),
      summary: generate_summary(projected, needed)
    }
  end

  # Greedily add the dimension that grows the covered-ingredient union the most,
  # stopping once the union reaches `target` (or we run out of dimensions).
  defp find_minimal_set(fields, total, target) do
    select_fields(fields, MapSet.new(), [], total, target)
  end

  defp select_fields(remaining, union, acc, total, target) do
    coverage = coverage_of(union, total)

    if coverage >= target or remaining == [] do
      {Enum.reverse(acc), coverage}
    else
      best = Enum.max_by(remaining, &new_ids_count(&1, union))
      new_union = MapSet.union(union, MapSet.new(best.matched_ids))
      select_fields(List.delete(remaining, best), new_union, [best | acc], total, target)
    end
  end

  defp new_ids_count(field, union) do
    field.matched_ids
    |> MapSet.new()
    |> MapSet.difference(union)
    |> MapSet.size()
  end

  defp covered_ids(fields, filter) do
    fields
    |> Enum.filter(filter)
    |> Enum.flat_map(& &1.matched_ids)
    |> MapSet.new()
  end

  defp coverage_of(_union, 0), do: 0.0
  defp coverage_of(union, total), do: MapSet.size(union) / total

  @doc """
  Fraction of ingredients with a linked `canonical_food` parse. This measures
  parser throughput, **not** per-dimension schema coverage.
  """
  @spec parse_fill_rate() :: float()
  def parse_fill_rate do
    total = Repo.aggregate(Ingredient, :count)

    if total == 0 do
      0.0
    else
      parsed =
        Repo.aggregate(
          from(p in IngredientParsedFood, where: not is_nil(p.canonical_food_id)),
          :count
        )

      parsed / total
    end
  end

  # Only propose columns for dimensions the parser does not already capture.
  defp generate_migration(fields) do
    fields
    |> Enum.filter(& &1.new_column?)
    |> Enum.map(fn field ->
      field_name = field.field
      coverage_pct = round(field.coverage * 100)

      top_values = Enum.map_join(field.top_values, ", ", & &1.value)

      """
      -- Add #{field_name} field (matches #{coverage_pct}% of ingredients)
      -- Example values: #{top_values}

      ALTER TABLE ingredient_parsed_foods
      ADD COLUMN #{field_name} TEXT;

      -- Index for faster queries
      CREATE INDEX idx_ingredient_parsed_foods_#{field_name}
      ON ingredient_parsed_foods(#{field_name});
      """
    end)
  end

  defp generate_summary(projected, fields) do
    {new_cols, existing} = Enum.split_with(fields, & &1.new_column?)

    """
    Projected dimension coverage: #{round(projected * 100)}%
    New columns to add: #{names(new_cols)}
    Already captured by parser: #{names(existing)}
    """
  end

  defp names([]), do: "(none)"
  defp names(fields), do: Enum.map_join(fields, ", ", & &1.field)
end
