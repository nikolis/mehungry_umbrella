defmodule Mehungry.FoodData.Usda.SchemaMatcherTest do
  # async: false — the reference-file test mutates the global app env. Assertions
  # are scoped to the ingredients seeded here so the pre-seeded corpus (parsed
  # against the fixture vocabulary) doesn't matter.
  use Mehungry.DataCase, async: false

  import Mehungry.ParserFixtures

  alias Mehungry.Food.Ingredient
  alias Mehungry.FoodData.Usda.SchemaMatcher

  defp seed(name) do
    Repo.insert!(%Ingredient{
      name: name,
      description: "d",
      url: "http://example.com",
      fdc_id: System.unique_integer([:positive])
    })
  end

  defp find_schema(schemas, dims), do: Enum.find(schemas, &(&1.dimensions == dims))

  defp matched_names(schema), do: Enum.map(schema.matched, & &1.name)

  defp unmatched_reason(analysis, name) do
    Enum.find_value(analysis.unmatched, fn
      %{ingredient: %{name: ^name}, reason: reason} -> reason
      _ -> nil
    end)
  end

  describe "analyze/1 with the ingredient corpus as the catalog source" do
    setup do
      # No reference file configured → the catalog is derived from the DB corpus.
      Application.put_env(:mehungry, :usda_schema_reference_paths, [])
      :ok
    end

    test "groups matched ingredients by parser signature" do
      seed("Carrot, raw")
      seed("Corn, raw")
      seed("Tomato, puree, canned")

      analysis = SchemaMatcher.analyze(vocabulary: vocabulary())

      assert analysis.source == :ingredients

      # "raw" foods share one schema; both of mine land in it.
      raw = find_schema(analysis.schemas, [:canonical_food, :processing])
      assert "Carrot, raw" in matched_names(raw)
      assert "Corn, raw" in matched_names(raw)

      # "puree, canned" is its own schema.
      canned = find_schema(analysis.schemas, [:canonical_food, :processing, :packaging])
      assert "Tomato, puree, canned" in matched_names(canned)
    end

    test "the predefined Alcoholic Beverage pattern wins over the parser skip" do
      # The deterministic parser skips these; the predefined pattern claims them.
      seed("Alcoholic Beverage, wine, table, red, Burgundy")
      seed("Alcoholic beverage, wine, table, red")

      analysis = SchemaMatcher.analyze(vocabulary: vocabulary())

      beverage =
        find_schema(analysis.schemas, [
          :type,
          :canonical_food,
          :beverage_sub_type,
          :color,
          :variety
        ])

      assert beverage.label == "Alcoholic Beverage"
      assert "Alcoholic Beverage, wine, table, red, Burgundy" in matched_names(beverage)
      assert "Alcoholic beverage, wine, table, red" in matched_names(beverage)

      # No longer set aside as unparseable.
      assert unmatched_reason(analysis, "Alcoholic Beverage, wine, table, red, Burgundy") == nil
    end
  end

  describe "analyze/1 with a reference dataset as the catalog source" do
    setup do
      path =
        Path.join(System.tmp_dir!(), "usda_schema_ref_#{System.unique_integer([:positive])}.json")

      File.write!(
        path,
        Jason.encode!(%{"FoundationFoods" => [%{"description" => "Carrot, raw"}]})
      )

      Application.put_env(:mehungry, :usda_schema_reference_paths, [path])

      on_exit(fn ->
        Application.put_env(:mehungry, :usda_schema_reference_paths, [])
        File.rm(path)
      end)

      :ok
    end

    test "an ingredient whose signature is absent from the catalog is set aside" do
      # "Corn, raw" shares the reference signature; "Tomato, puree, canned" does not.
      seed("Corn, raw")
      seed("Tomato, puree, canned")

      analysis = SchemaMatcher.analyze(vocabulary: vocabulary())

      assert analysis.source == :reference_files
      # One derived schema (from the single reference description) plus the
      # always-present predefined Alcoholic Beverage pattern.
      assert analysis.schema_count == 2

      schema = find_schema(analysis.schemas, [:canonical_food, :processing])
      assert "Corn, raw" in matched_names(schema)

      assert unmatched_reason(analysis, "Tomato, puree, canned") == "no matching schema"
    end
  end
end
