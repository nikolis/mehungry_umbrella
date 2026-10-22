defmodule MehungryWeb.Api.V1.RecipeFeedTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.Food.{Compounds, FoundementalFoods, SpeciesCompounds}
  alias Mehungry.FoodFixtures
  alias Mehungry.MealBlueprints

  defp author, do: AccountsFixtures.user_fixture()

  defp recipe_with_post(user) do
    recipe = FoodFixtures.recipe_fixture(user)
    {:ok, _post} = Mehungry.Posts.create_post(recipe)
    recipe
  end

  # A public blueprint requiring `compound`, plus a recipe whose single ingredient
  # carries that compound (species-fact path) — so matching yields one match.
  defp blueprint_and_matching_recipe(compound) do
    owner = author()

    attrs =
      MealBlueprints.default_blueprint_attrs(owner.id, "BP #{System.unique_integer([:positive])}")
      |> Map.put(:visibility, "public")
      |> Map.put(:required_compounds, [compound])

    {:ok, blueprint} = MealBlueprints.create_blueprint(attrs)

    ingredient = FoodFixtures.ingredient_fixture()
    mu = FoodFixtures.measurement_unit_fixture()

    {:ok, species} =
      FoundementalFoods.create_species(%{name: "species-#{System.unique_integer()}"})

    {:ok, _} =
      FoundementalFoods.create_foundemental_food(%{
        foundemental_species_id: species.id,
        usda_name: "usda-#{System.unique_integer()}",
        ingredient_id: ingredient.id
      })

    {:ok, cmp} = Compounds.create_compound(%{name: compound, compound_type: "oxalate"})

    {:ok, _} =
      SpeciesCompounds.upsert_species_relationship(%{
        foundemental_species_id: species.id,
        compound_id: cmp.id,
        relationship_type: "contains",
        source: "manual"
      })

    recipe =
      FoodFixtures.recipe_fixture(owner, %{
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}
        ]
      })

    %{blueprint: blueprint, recipe: recipe}
  end

  describe "GET /api/v1/feed" do
    test "returns the envelope with meta even when empty", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/feed")
      assert %{"data" => data, "meta" => %{"page" => 1, "has_more" => _}} = json_response(conn, 200)
      assert is_list(data)
    end

    test "includes a published recipe card", %{conn: conn} do
      recipe = recipe_with_post(author())
      conn = get(conn, ~p"/api/v1/feed")
      assert %{"data" => cards} = json_response(conn, 200)
      card = Enum.find(cards, &(&1["id"] == recipe.id))
      assert card["title"] == recipe.title
      assert card["liked_by_me"] == false
      assert Map.has_key?(card, "likes_count")
      assert Map.has_key?(card, "author")
    end
  end

  describe "GET /api/v1/recipes/:id" do
    test "returns full detail", %{conn: conn} do
      recipe = FoodFixtures.recipe_fixture(author())
      conn = get(conn, ~p"/api/v1/recipes/#{recipe.id}")

      assert %{"data" => detail} = json_response(conn, 200)
      assert detail["id"] == recipe.id
      assert is_list(detail["ingredients"])
      assert Map.has_key?(detail, "nutrients")
      assert Map.has_key?(detail, "likes_count")
      assert is_list(detail["badges"])
    end

    test "exposes persisted nutrient-claim badges", %{conn: conn} do
      recipe =
        FoodFixtures.recipe_fixture(author())
        |> Ecto.Changeset.change(%{
          badges: [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}]
        })
        |> Mehungry.Repo.update!()

      detail = get(conn, ~p"/api/v1/recipes/#{recipe.id}") |> json_response(200) |> Map.fetch!("data")

      assert [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}] = detail["badges"]
    end

    test "localizes nutrient display names with ?lang=el", %{conn: conn} do
      recipe =
        FoodFixtures.recipe_fixture(author(), %{
          nutrients: %{"Energy" => %{"name" => "Energy", "amount" => 50.0, "unit" => "kcal"}}
        })

      en = get(conn, ~p"/api/v1/recipes/#{recipe.id}") |> json_response(200)
      assert Map.has_key?(en["data"]["nutrients"], "Energy")

      el = get(conn, ~p"/api/v1/recipes/#{recipe.id}?lang=el") |> json_response(200)
      assert Map.has_key?(el["data"]["nutrients"], "Ενέργεια")
      refute Map.has_key?(el["data"]["nutrients"], "Energy")
    end

    test "404 for a missing recipe", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/recipes/99999999")
      assert json_response(conn, 404)
    end

    test "error detail is localized to the request locale", %{conn: conn} do
      en = get(conn, ~p"/api/v1/recipes/99999999") |> json_response(404)
      assert en["errors"]["detail"] == "Not found"

      el = get(conn, ~p"/api/v1/recipes/99999999?lang=el") |> json_response(404)
      assert el["errors"]["detail"] == "Δεν βρέθηκε"
    end

    test "localizes recipe title/description with ?lang=el", %{conn: conn} do
      {:ok, _lang} = Mehungry.Languages.create_language(%{name: "el"})
      recipe = FoodFixtures.recipe_fixture(author())

      {:ok, _translation} =
        %Mehungry.AI.Bot.RecipeTranslation{}
        |> Mehungry.AI.Bot.RecipeTranslation.changeset(%{
          recipe_id: recipe.id,
          language_name: "el",
          title: "Ελληνικός τίτλος",
          description: "Ελληνική περιγραφή"
        })
        |> Mehungry.Repo.insert()

      en = get(conn, ~p"/api/v1/recipes/#{recipe.id}") |> json_response(200)
      assert en["data"]["title"] == recipe.title

      el = get(conn, ~p"/api/v1/recipes/#{recipe.id}?lang=el") |> json_response(200)
      assert el["data"]["title"] == "Ελληνικός τίτλος"
      assert el["data"]["description"] == "Ελληνική περιγραφή"
    end

    test "localizes ingredient names with ?lang=el even without a recipe translation",
         %{conn: conn} do
      {:ok, _lang} = Mehungry.Languages.create_language(%{name: "el"})

      translated = FoodFixtures.ingredient_fixture(%{name: "Eggplant"})
      untranslated = FoodFixtures.ingredient_fixture(%{name: "Zucchini"})
      mu = FoodFixtures.measurement_unit_fixture()

      recipe =
        FoodFixtures.recipe_fixture(author(), %{
          recipe_ingredients: [
            %{ingredient_id: translated.id, measurement_unit_id: mu.id, quantity: 2},
            %{ingredient_id: untranslated.id, measurement_unit_id: mu.id, quantity: 1}
          ]
        })

      {:ok, _} = Mehungry.Food.upsert_ingredient_translation(translated.id, "el", "Μελιτζάνα")

      # No `RecipeTranslation` exists — ingredient localization is decoupled from it.
      el = get(conn, ~p"/api/v1/recipes/#{recipe.id}?lang=el") |> json_response(200)
      ingredients = el["data"]["ingredients"]

      names =
        Map.new(ingredients, fn ing -> {ing["ingredient"]["id"], ing["ingredient"]["name"]} end)

      assert names[translated.id] == "Μελιτζάνα"
      # the untranslated ingredient is KEPT (not dropped) and falls back to English
      assert names[untranslated.id] == "Zucchini"
      # recipe_ingredient ids survive localization (serializer needs them for edits)
      assert Enum.all?(ingredients, & &1["id"])

      # English request is unaffected.
      en = get(conn, ~p"/api/v1/recipes/#{recipe.id}") |> json_response(200)
      en_names = Enum.map(en["data"]["ingredients"], & &1["ingredient"]["name"])
      assert "Eggplant" in en_names and "Zucchini" in en_names
    end

    test "404 for another user's private recipe", %{conn: conn} do
      recipe = FoodFixtures.recipe_fixture(author(), %{private: true})
      conn = get(conn, ~p"/api/v1/recipes/#{recipe.id}")
      assert json_response(conn, 404)
    end

    test "omits blueprint_match without ?blueprint_slug=", %{conn: conn} do
      recipe = FoodFixtures.recipe_fixture(author())
      conn = get(conn, ~p"/api/v1/recipes/#{recipe.id}")
      assert %{"data" => detail} = json_response(conn, 200)
      refute Map.has_key?(detail, "blueprint_match")
    end

    test "includes blueprint_match for ?blueprint_slug=", %{conn: conn} do
      %{blueprint: bp, recipe: recipe} = blueprint_and_matching_recipe("Oxalate")

      conn = get(conn, ~p"/api/v1/recipes/#{recipe.id}?blueprint_slug=#{bp.slug}")
      assert %{"data" => detail} = json_response(conn, 200)

      assert %{"blueprint_slug" => slug, "matches" => matches, "match_count" => 1} =
               detail["blueprint_match"]

      assert slug == bp.slug
      assert [%{"kind" => "compound", "name" => "Oxalate", "direction" => "required"}] = matches
    end

    test "ignores an unknown ?blueprint_slug= (no match key)", %{conn: conn} do
      recipe = FoodFixtures.recipe_fixture(author())
      conn = get(conn, ~p"/api/v1/recipes/#{recipe.id}?blueprint_slug=no-such-bp")
      assert %{"data" => detail} = json_response(conn, 200)
      refute Map.has_key?(detail, "blueprint_match")
    end
  end

  describe "recipe CRUD" do
    setup :register_and_log_in_api_user

    test "POST creates a recipe", %{conn: conn} do
      ingredient = FoodFixtures.ingredient_fixture()
      mu = FoodFixtures.measurement_unit_fixture()

      body = %{
        "title" => "API Stew #{System.unique_integer([:positive])}",
        "description" => "tasty",
        "servings" => 4,
        "difficulty" => 2,
        "cousine" => "Mediterranean",
        "preperation_time_lower_limit" => 20,
        "cooking_time_lower_limit" => 40,
        "image_url" => "https://example.com/x.jpg",
        "recipe_ingredients" => [
          %{"ingredient_id" => ingredient.id, "measurement_unit_id" => mu.id, "quantity" => 2.0}
        ],
        "steps" => [%{"index" => 1, "title" => "Roast", "description" => "Roast it"}]
      }

      conn = post(conn, ~p"/api/v1/recipes", body)
      assert %{"data" => detail} = json_response(conn, 201)
      assert detail["title"] == body["title"]
      assert detail["servings"] == 4
    end

    test "DELETE removes an owned recipe; 403 for others", %{conn: conn, user: user} do
      own = FoodFixtures.recipe_fixture(user)
      others = FoodFixtures.recipe_fixture(author())

      assert conn |> delete(~p"/api/v1/recipes/#{own.id}") |> response(204)
      assert conn |> delete(~p"/api/v1/recipes/#{others.id}") |> json_response(403)
    end
  end
end
