defmodule MehungryWeb.Api.V1.IngredientMealTest do
  @moduledoc """
  Parity between the mobile API and the calendar meal form for logging an
  *ingredient* (not a recipe) into a meal: the local-ingredient search exposes
  each ingredient's unit/portion options, and meal create accepts the same
  signed `unit_selection` the LiveView uses.
  """
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Food
  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  describe "GET /api/v1/ingredients/search?source=local" do
    test "returns matching ingredients each with their unit options", %{conn: conn} do
      ingredient = FoodFixtures.ingredient_fixture(%{name: "Banana parity"})

      {:ok, portion} =
        Food.create_ingredient_portion(%{
          ingredient_id: ingredient.id,
          description: "1 medium banana",
          gram_weight: 118.0
        })

      resp =
        conn
        |> get(~p"/api/v1/ingredients/search?q=Banana%20parity&source=local")
        |> json_response(200)

      assert %{"data" => [hit | _]} = resp
      assert hit["id"] == ingredient.id
      assert hit["name"] == "Banana parity"

      units = hit["units"]

      # The description-only portion encodes as the negative picker value and
      # carries its ingredient_portion_id (measurement_unit_id null).
      assert Enum.any?(units, fn u ->
               u["ingredient_portion_id"] == portion.id and
                 u["unit_selection"] == -portion.id and
                 is_nil(u["measurement_unit_id"]) and
                 u["label"] == "1 medium banana"
             end)

      # "gram" is always appended, as a positive measurement_unit_id.
      assert Enum.any?(units, fn u ->
               u["label"] == "gram" and u["measurement_unit_id"] == u["unit_selection"] and
                 is_nil(u["ingredient_portion_id"])
             end)
    end

    test "?lang=el searches and labels translated ingredient names", %{conn: conn} do
      Mehungry.Languages.ensure_language("el")
      ingredient = FoodFixtures.ingredient_fixture(%{name: "Banana parity el"})
      {:ok, _} = Food.Localization.upsert_ingredient_translation(ingredient.id, "el", "Μπανάνα τεστ")

      resp =
        conn
        |> get(~p"/api/v1/ingredients/search?q=Μπανάνα&source=local&lang=el")
        |> json_response(200)

      assert %{"data" => hits} = resp
      assert Enum.any?(hits, &(&1["id"] == ingredient.id and &1["name"] == "Μπανάνα τεστ"))
    end

    test "default (no source) still routes to the USDA branch, not local", %{conn: conn} do
      _ingredient = FoodFixtures.ingredient_fixture(%{name: "Onion parity"})

      # Without source=local the request goes to the USDA client (unreachable in
      # test → 400), never the local `units`-bearing branch. This pins that the
      # existing basket/recipe search contract is unchanged.
      assert conn |> get(~p"/api/v1/ingredients/search?q=Onion%20parity") |> response(400)
    end
  end

  describe "POST /api/v1/meals with an ingredient_user_meal" do
    test "logs a description-only portion via unit_selection and round-trips it", %{conn: conn} do
      ingredient = FoodFixtures.ingredient_fixture(%{})

      {:ok, portion} =
        Food.create_ingredient_portion(%{
          ingredient_id: ingredient.id,
          description: "1 slice",
          gram_weight: 30.0
        })

      body = %{
        "date" => "2026-08-12",
        "meal_type" => "lunch",
        "ingredient_user_meals" => [
          %{"ingredient_id" => ingredient.id, "unit_selection" => -portion.id, "quantity" => 2}
        ]
      }

      created = conn |> post(~p"/api/v1/meals", body) |> json_response(201)
      assert %{"data" => %{"ingredients" => [ing]}} = created

      assert ing["ingredient_id"] == ingredient.id
      assert ing["quantity"] == 2.0
      # unit_selection split into the portion FK (no measurement unit), and the
      # signed picker value echoes back for a lossless edit.
      assert ing["ingredient_portion_id"] == portion.id
      assert is_nil(ing["measurement_unit_id"])
      assert ing["unit_selection"] == -portion.id
    end

    test "logs a unit-based row via explicit measurement_unit_id", %{conn: conn} do
      ingredient = FoodFixtures.ingredient_fixture(%{})
      mu_id = ingredient.measurement_unit_id

      body = %{
        "date" => "2026-08-12",
        "meal_type" => "dinner",
        "ingredient_user_meals" => [
          %{"ingredient_id" => ingredient.id, "measurement_unit_id" => mu_id, "quantity" => 100}
        ]
      }

      created = conn |> post(~p"/api/v1/meals", body) |> json_response(201)
      assert %{"data" => %{"ingredients" => [ing]}} = created
      assert ing["measurement_unit_id"] == mu_id
      assert is_nil(ing["ingredient_portion_id"])
      assert ing["unit_selection"] == mu_id
    end
  end
end
