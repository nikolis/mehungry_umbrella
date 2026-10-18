defmodule MehungryWeb.Api.V1.MealTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  test "create, list in range, then delete a meal", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user)

    body = %{
      "date" => "2026-08-12",
      "meal_type" => "dinner",
      "recipe_user_meals" => [%{"recipe_id" => recipe.id, "servings" => 2}]
    }

    created = conn |> post(~p"/api/v1/meals", body) |> json_response(201)
    assert %{"data" => %{"id" => meal_id, "meal_type" => "dinner", "recipes" => recipes}} = created
    assert [%{"recipe_id" => rid, "servings" => 2}] = recipes
    assert rid == recipe.id

    listed = conn |> get(~p"/api/v1/meals?start=2026-08-10&end=2026-08-16") |> json_response(200)
    assert %{"data" => %{"days" => days, "meal_type_vocabulary" => vocab}} = listed
    assert Enum.any?(days, fn d -> d["date"] == "2026-08-12" end)
    assert Enum.any?(vocab, &(&1["key"] == "dinner"))

    assert conn |> delete(~p"/api/v1/meals/#{meal_id}") |> response(204)
  end

  test "create an unsorted (nil meal_type) meal", %{conn: conn} do
    body = %{"date" => "2026-08-12", "meal_type" => nil, "title" => "Snacks"}
    created = conn |> post(~p"/api/v1/meals", body) |> json_response(201)
    assert %{"data" => %{"meal_type" => nil, "title" => "Snacks"}} = created
  end

  test "GET /meals requires start and end", %{conn: conn} do
    assert conn |> get(~p"/api/v1/meals") |> json_response(400)
  end

  test "day nutrition returns an envelope", %{conn: conn} do
    assert %{"data" => %{"date" => "2026-08-12", "nutrition" => _}} =
             conn |> get(~p"/api/v1/meals/day/2026-08-12/nutrition") |> json_response(200)
  end

  test "day nutrition aggregates a logged recipe meal, scaled to consumed portions", %{
    conn: conn,
    user: user
  } do
    recipe =
      FoodFixtures.recipe_fixture(user, %{
        servings: 4,
        nutrients: %{"Energy" => %{"amount" => 200.0, "unit" => "kcal"}}
      })

    body = %{
      "date" => "2026-08-12",
      "meal_type" => "dinner",
      "recipe_user_meals" => [%{"recipe_id" => recipe.id, "servings" => 2}]
    }

    assert conn |> post(~p"/api/v1/meals", body) |> json_response(201)

    assert %{"data" => %{"nutrition" => nutrition}} =
             conn |> get(~p"/api/v1/meals/day/2026-08-12/nutrition") |> json_response(200)

    # 2 of 4 servings consumed → half the recipe's 200 kcal.
    assert %{"Energy" => %{"amount" => 100.0}} = nutrition
  end

  test "day nutrition localizes nutrient names to the request locale", %{conn: conn, user: user} do
    recipe =
      FoodFixtures.recipe_fixture(user, %{
        servings: 1,
        nutrients: %{"Energy" => %{"name" => "Energy", "amount" => 200.0, "unit" => "kcal"}}
      })

    body = %{
      "date" => "2026-08-12",
      "meal_type" => "dinner",
      "recipe_user_meals" => [%{"recipe_id" => recipe.id, "servings" => 1}]
    }

    assert conn |> post(~p"/api/v1/meals", body) |> json_response(201)

    # English (default): canonical English key.
    assert %{"data" => %{"nutrition" => %{"Energy" => _}}} =
             conn |> get(~p"/api/v1/meals/day/2026-08-12/nutrition") |> json_response(200)

    # ?lang=el: the key and node name are the Greek display label.
    assert %{"data" => %{"nutrition" => el_nutrition}} =
             conn |> get(~p"/api/v1/meals/day/2026-08-12/nutrition?lang=el") |> json_response(200)

    assert %{"Ενέργεια" => %{"name" => "Ενέργεια"}} = el_nutrition
    refute Map.has_key?(el_nutrition, "Energy")
  end

  describe "free food (arbitrary) entries" do
    @per_100g [
      %{"name" => "Energy", "unit" => "kcal", "amount" => 250},
      %{"name" => "Protein", "unit" => "g", "amount" => 12}
    ]

    test "grams mode: logs, round-trips, and scales into the day nutrition", %{conn: conn} do
      body = %{
        "date" => "2026-08-12",
        "meal_type" => "dinner",
        "free_food_user_meals" => [
          %{"name" => "Big Mac", "nutrients_per_100g" => @per_100g, "grams" => 250}
        ]
      }

      created = conn |> post(~p"/api/v1/meals", body) |> json_response(201)
      assert %{"data" => %{"free_foods" => [ff]}} = created
      assert %{"name" => "Big Mac", "grams" => 250.0, "nutrients_per_100g" => returned} = ff
      assert Enum.any?(returned, &(&1["name"] == "Energy" and &1["amount"] == 250))

      assert %{"data" => %{"nutrition" => nutrition}} =
               conn |> get(~p"/api/v1/meals/day/2026-08-12/nutrition") |> json_response(200)

      # 250 kcal/100g × 250 g / 100 = 625 kcal; 12 g/100g × 2.5 = 30 g protein.
      assert %{"Energy" => %{"amount" => 625.0}, "Protein" => %{"amount" => 30.0}} = nutrition
    end

    test "portion mode: resolves grams = portion_grams × portions", %{conn: conn} do
      body = %{
        "date" => "2026-08-12",
        "meal_type" => "lunch",
        "free_food_user_meals" => [
          %{
            "name" => "Souvlaki",
            "nutrients_per_100g" => @per_100g,
            "portion_name" => "stick",
            "portion_grams" => 150,
            "portions" => 2
          }
        ]
      }

      created = conn |> post(~p"/api/v1/meals", body) |> json_response(201)
      assert %{"data" => %{"free_foods" => [ff]}} = created
      assert %{"grams" => 300.0, "portion_name" => "stick", "portions" => 2.0} = ff

      assert %{"data" => %{"nutrition" => nutrition}} =
               conn |> get(~p"/api/v1/meals/day/2026-08-12/nutrition") |> json_response(200)

      # 250 kcal/100g × 300 g / 100 = 750 kcal.
      assert %{"Energy" => %{"amount" => 750.0}} = nutrition
    end

    test "is isolated — creates no Recipe or Ingredient rows", %{conn: conn} do
      recipes_before = Mehungry.Repo.aggregate(Mehungry.Food.Recipe, :count)
      ingredients_before = Mehungry.Repo.aggregate(Mehungry.Food.Ingredient, :count)

      body = %{
        "date" => "2026-08-12",
        "meal_type" => "dinner",
        "free_food_user_meals" => [
          %{"name" => "Mystery snack", "nutrients_per_100g" => @per_100g, "grams" => 100}
        ]
      }

      assert conn |> post(~p"/api/v1/meals", body) |> json_response(201)

      assert Mehungry.Repo.aggregate(Mehungry.Food.Recipe, :count) == recipes_before
      assert Mehungry.Repo.aggregate(Mehungry.Food.Ingredient, :count) == ingredients_before
    end

    test "rejects an entry with no grams and no portion pair", %{conn: conn} do
      body = %{
        "date" => "2026-08-12",
        "meal_type" => "dinner",
        "free_food_user_meals" => [
          %{"name" => "No amount", "nutrients_per_100g" => @per_100g}
        ]
      }

      assert conn |> post(~p"/api/v1/meals", body) |> json_response(422)
    end
  end

  test "deleting another user's meal 404s", %{conn: conn} do
    other = Mehungry.AccountsFixtures.user_fixture()
    recipe = FoodFixtures.recipe_fixture(other)

    {:ok, meal} =
      Mehungry.History.create_user_meal(%{
        "user_id" => other.id,
        "title" => "Theirs",
        "meal_type" => "lunch",
        "start_dt" => ~N[2026-08-12 13:00:00],
        "end_dt" => ~N[2026-08-12 13:30:00],
        "recipe_user_meals" => [
          %{"recipe_id" => recipe.id, "consume_portions" => 1, "cooking_portions" => 1}
        ]
      })

    assert conn |> delete(~p"/api/v1/meals/#{meal.id}") |> json_response(404)
  end

  describe "plan-with-ai" do
    test "403 upgrade when out of quota (free tier)", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/meals/plan-with-ai", %{"start" => "2026-08-11", "days" => 5})
      assert %{"errors" => %{"upgrade" => true}} = json_response(conn, 403)
    end

    test "202 + job id when quota available, then poll", %{conn: conn, user: user} do
      {:ok, _sub} = Mehungry.Subscriptions.upsert_subscription(user.id, %{tier: "m3hungry_plus"})

      accepted =
        conn
        |> post(~p"/api/v1/meals/plan-with-ai", %{"start" => "2026-08-11", "days" => 5, "notes" => "high protein"})
        |> json_response(202)

      assert %{"data" => %{"job_id" => job_id, "status" => "queued"}} = accepted

      polled = conn |> get(~p"/api/v1/meals/plan-with-ai/#{job_id}") |> json_response(200)
      assert %{"data" => %{"job_id" => ^job_id, "status" => "queued"}} = polled
    end

    test "polling another user's job 404s", %{conn: conn} do
      other = Mehungry.AccountsFixtures.user_fixture()
      {:ok, job} = Mehungry.MealPlanJobs.create_job(%{user_id: other.id, status: "queued"})
      assert conn |> get(~p"/api/v1/meals/plan-with-ai/#{job.id}") |> json_response(404)
    end
  end
end
