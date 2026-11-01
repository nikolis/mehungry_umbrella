defmodule Mehungry.FoodData.Usda.ImporterTest do
  use Mehungry.DataCase, async: false

  import Ecto.Query

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientNutrient, IngredientPortion}
  alias Mehungry.FoodData.Usda.Importer

  # Minimal FDC `/food/{id}` detail payload in the public-API shape that
  # FoodParser.create_ingredient/2 consumes.
  defp fdc_food(fdc_id, description) do
    %{
      "fdcId" => fdc_id,
      "description" => description,
      "dataType" => "SR Legacy",
      "foodClass" => "FinalFood",
      "foodCategory" => %{"description" => "Sweets", "code" => "1900"},
      "foodNutrients" => [
        %{
          "amount" => 598.0,
          "type" => "FoodNutrient",
          "nutrient" => %{
            "id" => 1008,
            "number" => "208",
            "name" => "Energy",
            "rank" => 300,
            "unitName" => "kcal"
          }
        }
      ],
      "foodPortions" => [
        %{
          "id" => 1,
          "amount" => 1.0,
          "gramWeight" => 100.0,
          "sequenceNumber" => 1,
          "measureUnit" => %{"id" => 1000, "name" => "gram"}
        }
      ]
    }
  end

  setup do
    # Stub the FDC HTTP seam so no network round-trip happens. The adapter is
    # keyed off the `fdcId` in the URL so a batch of ids each resolve correctly.
    Application.put_env(:mehungry, :fdc_http_adapter, fn url, _headers, _opts ->
      cond do
        String.contains?(url, "/food/175040") ->
          {:ok, %{status_code: 200, body: Jason.encode!(fdc_food(175_040, "Leavening agents, baking soda")), headers: []}}

        String.contains?(url, "/food/170273") ->
          {:ok, %{status_code: 200, body: Jason.encode!(fdc_food(170_273, "Chocolate, dark, 70-85% cacao solids")), headers: []}}

        # A record the API serves but with no usable description. Returned as a
        # 200 (not a 404) so it stays fully offline — a 404 would make FdcClient
        # fall back to the real USDA portal host over the network.
        String.contains?(url, "/food/404404") ->
          {:ok, %{status_code: 200, body: Jason.encode!(%{"fdcId" => 404_404}), headers: []}}

        true ->
          {:ok, %{status_code: 200, body: Jason.encode!(%{"foods" => []}), headers: []}}
      end
    end)

    Application.put_env(:mehungry, :fdc_api_key, "test-key")

    on_exit(fn ->
      Application.delete_env(:mehungry, :fdc_http_adapter)
      Application.delete_env(:mehungry, :fdc_api_key)
    end)

    :ok
  end

  describe "import_by_fdc_id/1" do
    test "persists the food with its USDA nutrients and portions" do
      assert {:ok, ingredient} = Importer.import_by_fdc_id(175_040)
      assert ingredient.name == "Leavening agents, baking soda"
      assert ingredient.fdc_id == 175_040
      assert ingredient.nutrient_data_source == "usda"
      assert ingredient.category_id

      nutrients =
        Repo.all(from n in IngredientNutrient, where: n.ingredient_id == ^ingredient.id)

      portions =
        Repo.all(from p in IngredientPortion, where: p.ingredient_id == ^ingredient.id)

      assert length(nutrients) == 1
      assert length(portions) == 1
    end

    test "is idempotent — re-importing the same id upserts rather than duplicating" do
      assert {:ok, _} = Importer.import_by_fdc_id(170_273)
      assert {:ok, _} = Importer.import_by_fdc_id(170_273)

      count =
        Repo.aggregate(
          from(i in Ingredient, where: i.name == "Chocolate, dark, 70-85% cacao solids"),
          :count
        )

      assert count == 1
    end

    test "returns an error tuple for a record with no usable name" do
      assert {:error, :no_description} = Importer.import_by_fdc_id(404_404)
    end
  end

  describe "import_by_fdc_ids/1" do
    test "returns a per-id result list and attempts every id" do
      results = Importer.import_by_fdc_ids([175_040, 404_404, 170_273])

      assert {175_040, :ok, "Leavening agents, baking soda"} in results
      assert {170_273, :ok, "Chocolate, dark, 70-85% cacao solids"} in results
      assert Enum.any?(results, fn {id, status, _} -> id == 404_404 and status == :error end)
    end
  end
end
