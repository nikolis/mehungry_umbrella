defmodule Mehungry.Food.SchemaDiscoveryTest do
  use Mehungry.DataCase, async: true

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.SchemaDiscovery.{Coverage, PureEx}

  # Each name carries a distinct grade value (existing column) *and* a distinct
  # size value (un-captured), so both dimensions clear the ≥5 distinct-value bar
  # and match the same ingredients — exercising the union math and the dedupe.
  # Assertions are scoped to *these* ids so pre-seeded ingredients don't matter.
  @multi [
    "large beef choice",
    "medium beef select",
    "small beef prime",
    "jumbo beef standard",
    "mini beef cutter",
    "giant beef canner"
  ]

  # No grade token: "selected" must NOT be read as the "select" grade.
  @false_positive "carefully selected beef"

  defp seed do
    (@multi ++ [@false_positive])
    |> Enum.each(fn name ->
      Repo.insert!(%Ingredient{name: name, description: "d", url: "http://example.com"})
    end)
  end

  defp my_ids do
    Repo.all(from i in Ingredient, where: i.name in ^@multi, select: i.id) |> MapSet.new()
  end

  defp rec(recommendations, field), do: Enum.find(recommendations, &(&1.field == field))

  test "flags already-captured dimensions with their existing column" do
    seed()
    %{recommendations: recs} = PureEx.analyze()

    grade = rec(recs, :grade)
    assert grade.new_column? == false
    assert grade.existing_column == :grade

    size = rec(recs, :size)
    assert size.new_column? == true
    assert size.existing_column == nil
  end

  test "tightened grade regex rejects 'selected'" do
    seed()
    %{recommendations: recs} = PureEx.analyze()

    grade_values = rec(recs, :grade).top_values |> Enum.map(& &1.value)
    assert "select" in grade_values
    refute "selected" in grade_values
  end

  test "combined coverage is the union, not the sum" do
    seed()
    %{recommendations: recs} = PureEx.analyze()
    mine = my_ids()

    grade = MapSet.intersection(MapSet.new(rec(recs, :grade).matched_ids), mine)
    size = MapSet.intersection(MapSet.new(rec(recs, :size).matched_ids), mine)

    # Both dimensions match all six of my ingredients...
    assert MapSet.equal?(grade, mine)
    assert MapSet.equal?(size, mine)

    # ...so the naive sum double-counts (6 + 6), but the union is still 6.
    assert MapSet.size(grade) + MapSet.size(size) == 12
    assert MapSet.size(MapSet.union(grade, size)) == 6

    # And the top-level projection never exceeds 1.0.
    assert Coverage.recommend().projected_coverage <= 1.0
  end

  test "migrations propose only un-captured columns" do
    seed()
    report = Coverage.recommend()
    sql = Enum.join(report.migration_sql, "\n")

    # No dimension backed by an existing parser column may be proposed.
    for {_dim, %{column: col}} <- PureEx.patterns(), not is_nil(col) do
      refute sql =~ "ADD COLUMN #{col}"
    end

    # Every selected new-column dimension is proposed; every captured one is not.
    for field <- report.fields_needed do
      if field.new_column? do
        assert sql =~ "ADD COLUMN #{field.field}"
      else
        refute sql =~ "ADD COLUMN #{field.field}"
      end
    end
  end
end
