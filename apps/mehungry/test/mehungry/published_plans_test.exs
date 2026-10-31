defmodule Mehungry.PublishedPlansTest do
  @moduledoc """
  Covers publishing a calendar week as a public, crawlable meal plan: the
  self-contained snapshot (days with recipe links, macros, slug), public lookup,
  and the empty-week guard.
  """
  use Mehungry.DataCase

  alias Mehungry.PublishedPlans

  import Mehungry.AccountsFixtures
  import Mehungry.HistoryFixtures
  alias Mehungry.FoodFixtures

  # A Monday so the 7-day window is unambiguous.
  @week_start ~D[2026-10-05]

  describe "publish_week/3" do
    setup do
      user = user_fixture()
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Lentil Soup"})

      # One recipe meal on the Tuesday of the week.
      _meal =
        user_meal_fixture(%{
          user_id: user.id,
          title: "Lunch",
          meal_type: "lunch",
          start_dt: ~N[2026-10-06 12:00:00],
          end_dt: ~N[2026-10-06 13:00:00],
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
        })

      %{user: user, recipe: recipe}
    end

    test "publishes a public snapshot with 7 days and the recipe linked", %{
      user: user,
      recipe: recipe
    } do
      assert {:ok, plan} =
               PublishedPlans.publish_week(user, @week_start, goal_label: "Anti-inflammatory")

      assert plan.visibility == "public"
      assert plan.slug =~ ~r/anti-inflammatory/
      assert plan.title =~ "Anti-inflammatory"
      assert plan.user_id == user.id
      assert length(plan.days) == 7
      assert plan.recipe_count == 1
      assert is_binary(plan.summary_text)

      # The Tuesday (index 1) carries the recipe item with its id for linking.
      tuesday = Enum.find(plan.days, &(&1["index"] == 1))
      item = tuesday["meals"] |> hd() |> Map.get("items") |> hd()
      assert item["kind"] == "recipe"
      assert item["recipe_id"] == recipe.id
      assert item["title"] == recipe.title

      # Macro snapshot is present and keyed by the canonical labels.
      assert Map.has_key?(plan.macros, "energy_kcal")
      assert Map.has_key?(plan.macros, "protein_g")
    end

    test "grocery_groups buckets ingredients into aisles in canonical order", %{user: user} do
      veg = ensure_category("Vegetables and Vegetable Products")
      poultry = ensure_category("Poultry Products")
      {:ok, tomato} = Mehungry.Food.create_ingredient(%{name: "Tomato", category_id: veg.id})

      {:ok, chicken} =
        Mehungry.Food.create_ingredient(%{name: "Chicken breast", category_id: poultry.id})

      mu = FoodFixtures.measurement_unit_fixture()

      recipe =
        FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: tomato.id, measurement_unit_id: mu.id, quantity: 2},
            %{ingredient_id: chicken.id, measurement_unit_id: mu.id, quantity: 1}
          ]
        })

      user_meal_fixture(%{
        user_id: user.id,
        meal_type: "dinner",
        start_dt: ~N[2026-10-07 19:00:00],
        end_dt: ~N[2026-10-07 20:00:00],
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
      })

      {:ok, plan} = PublishedPlans.publish_week(user, @week_start)

      aisles = Enum.map(plan.grocery_groups, & &1["aisle"])
      # Produce precedes Meat & Seafood (canonical shop order), empty aisles dropped.
      assert "produce" in aisles
      assert "meat_seafood" in aisles

      assert Enum.find_index(aisles, &(&1 == "produce")) <
               Enum.find_index(aisles, &(&1 == "meat_seafood"))

      produce = Enum.find(plan.grocery_groups, &(&1["aisle"] == "produce"))
      meat = Enum.find(plan.grocery_groups, &(&1["aisle"] == "meat_seafood"))
      assert "Tomato" in Enum.map(produce["items"], & &1["name"])
      assert "Chicken breast" in Enum.map(meat["items"], & &1["name"])

      # Each recipe-sourced grocery item carries its ingredient_id so the public
      # page localizes it by id (not the fragile name-join).
      tomato_item = Enum.find(produce["items"], &(&1["name"] == "Tomato"))
      chicken_item = Enum.find(meat["items"], &(&1["name"] == "Chicken breast"))
      assert tomato_item["ingredient_id"] == tomato.id
      assert chicken_item["ingredient_id"] == chicken.id

      # The flat `grocery` list (names) stays in sync with the flattened groups.
      assert Enum.sort(plan.grocery) ==
               Enum.sort(Enum.flat_map(plan.grocery_groups, fn g -> Enum.map(g["items"], & &1["name"]) end))
    end

    test "a directly-logged ingredient carries its id in the grocery list", %{user: user} do
      veg = ensure_category("Vegetables and Vegetable Products")
      {:ok, onion} = Mehungry.Food.create_ingredient(%{name: "Onion", category_id: veg.id})
      mu = FoodFixtures.measurement_unit_fixture()

      user_meal_fixture(%{
        user_id: user.id,
        meal_type: "dinner",
        start_dt: ~N[2026-10-07 19:00:00],
        end_dt: ~N[2026-10-07 20:00:00],
        ingredient_user_meals: [
          %{ingredient_id: onion.id, measurement_unit_id: mu.id, quantity: 1}
        ]
      })

      {:ok, plan} = PublishedPlans.publish_week(user, @week_start)

      produce = Enum.find(plan.grocery_groups, &(&1["aisle"] == "produce"))
      onion_item = Enum.find(produce["items"], &(&1["name"] == "Onion"))
      assert onion_item["ingredient_id"] == onion.id
    end

    test "plain water is excluded from the grocery list", %{user: user} do
      bev = ensure_category("Beverages")
      veg = ensure_category("Vegetables and Vegetable Products")
      {:ok, water} = Mehungry.Food.create_ingredient(%{name: "Water, tap, municipal", category_id: bev.id})
      {:ok, melon} = Mehungry.Food.create_ingredient(%{name: "Watermelon", category_id: veg.id})
      mu = FoodFixtures.measurement_unit_fixture()

      recipe =
        FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: water.id, measurement_unit_id: mu.id, quantity: 500},
            %{ingredient_id: melon.id, measurement_unit_id: mu.id, quantity: 1}
          ]
        })

      user_meal_fixture(%{
        user_id: user.id,
        meal_type: "dinner",
        start_dt: ~N[2026-10-07 19:00:00],
        end_dt: ~N[2026-10-07 20:00:00],
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
      })

      {:ok, plan} = PublishedPlans.publish_week(user, @week_start)

      refute "Water, tap, municipal" in plan.grocery
      # ...but water-bearing foods are kept.
      assert "Watermelon" in plan.grocery
    end

    test "an ingredient used across meals appears once (deduped)", %{user: user} do
      veg = ensure_category("Vegetables and Vegetable Products")
      {:ok, onion} = Mehungry.Food.create_ingredient(%{name: "Onion", category_id: veg.id})
      mu = FoodFixtures.measurement_unit_fixture()

      recipe =
        FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [%{ingredient_id: onion.id, measurement_unit_id: mu.id, quantity: 1}]
        })

      # Same recipe on two different days of the week.
      for day <- [~N[2026-10-06 12:00:00], ~N[2026-10-08 12:00:00]] do
        user_meal_fixture(%{
          user_id: user.id,
          meal_type: "lunch",
          start_dt: day,
          end_dt: NaiveDateTime.add(day, 3600),
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
        })
      end

      {:ok, plan} = PublishedPlans.publish_week(user, @week_start)

      assert Enum.count(plan.grocery, &(&1 == "Onion")) == 1
    end

    test "empty week returns {:error, :empty_week}", %{user: user} do
      # A week with no meals (far from the seeded Tuesday).
      assert {:error, :empty_week} = PublishedPlans.publish_week(user, ~D[2026-12-07])
    end

    test "backfill_grocery_groups/0 groups a legacy flat-only plan by aisle", %{user: user} do
      veg = ensure_category("Vegetables and Vegetable Products")
      {:ok, _} = Mehungry.Food.create_ingredient(%{name: "Tomato", category_id: veg.id})

      # Simulate a plan published before aisle grouping: flat grocery, no groups.
      {:ok, legacy} =
        PublishedPlans.publish_week(user, @week_start)
        |> then(fn {:ok, p} -> Ecto.Changeset.change(p, grocery: ["Tomato"], grocery_groups: []) end)
        |> Mehungry.Repo.update()

      assert legacy.grocery_groups == []

      assert PublishedPlans.backfill_grocery_groups() >= 1

      reloaded = PublishedPlans.get_public_plan_by_slug!(legacy.slug)
      produce = Enum.find(reloaded.grocery_groups, &(&1["aisle"] == "produce"))
      assert Enum.map(produce["items"], & &1["name"]) == ["Tomato"]
      # Backfill resolves the id by matching the stored name (best-effort upgrade).
      assert hd(produce["items"])["ingredient_id"]
    end

    test "re-publishing the same week replaces in place: one plan, stable slug", %{user: user} do
      {:ok, a} = PublishedPlans.publish_week(user, @week_start, goal_label: "First")
      {:ok, b} = PublishedPlans.publish_week(user, @week_start, goal_label: "Second")

      # Same row, same URL — not a second plan.
      assert a.id == b.id
      assert a.slug == b.slug
      assert b.goal_label == "Second"

      # Exactly one plan exists for this user's week.
      assert PublishedPlans.list_plans_for_user(user.id) |> length() == 1
    end

    test "publishing a different week makes a separate plan", %{user: user} do
      {:ok, a} = PublishedPlans.publish_week(user, @week_start)
      # Seed a meal in a different week so it's not empty.
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Soup"})

      user_meal_fixture(%{
        user_id: user.id,
        meal_type: "lunch",
        start_dt: ~N[2026-10-13 12:00:00],
        end_dt: ~N[2026-10-13 13:00:00],
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
      })

      {:ok, b} = PublishedPlans.publish_week(user, ~D[2026-10-12])
      refute a.id == b.id
      assert PublishedPlans.list_plans_for_user(user.id) |> length() == 2
    end
  end

  describe "lookup" do
    setup do
      user = user_fixture()
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Greek Salad"})

      user_meal_fixture(%{
        user_id: user.id,
        title: "Dinner",
        meal_type: "dinner",
        start_dt: ~N[2026-10-07 19:00:00],
        end_dt: ~N[2026-10-07 20:00:00],
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
      })

      {:ok, plan} = PublishedPlans.publish_week(user, @week_start)
      %{user: user, plan: plan, recipe: recipe}
    end

    test "get_public_plan_by_slug/1 returns a public plan, nil for unknown", %{plan: plan} do
      assert PublishedPlans.get_public_plan_by_slug(plan.slug).id == plan.id
      assert PublishedPlans.get_public_plan_by_slug("does-not-exist") == nil
    end

    test "get_public_plan_by_slug/1 hides a private plan", %{plan: plan} do
      {:ok, _} = PublishedPlans.delete_plan(plan)
      refute PublishedPlans.get_public_plan_by_slug(plan.slug)
    end

    test "list_public_plans/1 includes the published slug", %{plan: plan} do
      slugs = PublishedPlans.list_public_plans() |> Enum.map(& &1.slug)
      assert plan.slug in slugs
    end

    test "list_plans_for_user/1 scopes to the owner", %{user: user, plan: plan} do
      other = user_fixture()
      assert PublishedPlans.list_plans_for_user(user.id) |> Enum.map(& &1.id) == [plan.id]
      assert PublishedPlans.list_plans_for_user(other.id) == []
    end

    test "get_user_plan!/2 returns the owner's plan but refuses a non-owner (IDOR)", %{
      user: user,
      plan: plan
    } do
      other = user_fixture()
      assert PublishedPlans.get_user_plan!(user.id, plan.id).id == plan.id

      assert_raise Ecto.NoResultsError, fn ->
        PublishedPlans.get_user_plan!(other.id, plan.id)
      end
    end

    test "import_to_calendar/3 re-creates the recipe meals on another user's week", %{
      plan: plan,
      recipe: recipe
    } do
      viewer = user_fixture()
      start_date = ~D[2026-11-02]

      assert {:ok, created, _skipped} =
               PublishedPlans.import_to_calendar(plan, viewer.id, start_date)

      assert created >= 1

      imported =
        Mehungry.History.list_calendar_user_meals(
          viewer.id,
          start_date,
          Date.add(start_date, 6)
        )

      recipe_ids =
        imported
        |> Enum.flat_map(& &1.recipe_user_meals)
        |> Enum.map(& &1.recipe_id)

      assert recipe.id in recipe_ids
    end

    test "a WEEKLY_PLAN feed post links to the published plan", %{user: user, plan: plan} do
      {:ok, graphic} =
        Mehungry.Food.create_weekly_plan_graphic(%{
          user_id: user.id,
          week_start: @week_start,
          image_url: "https://example.com/card.png"
        })

      {:ok, post} =
        Mehungry.Posts.create_weekly_plan_post(graphic, "My week",
          published_meal_plan_id: plan.id
        )

      assert post.published_meal_plan_id == plan.id
      # The feed loads the plan so the card can link to /meal-plans/:slug.
      assert Mehungry.Posts.get_post!(post.id).published_meal_plan.slug == plan.slug
    end

    test "re-posting a plan replaces its feed post (no duplicates)", %{user: user, plan: plan} do
      make_graphic = fn url ->
        {:ok, g} =
          Mehungry.Food.create_weekly_plan_graphic(%{
            user_id: user.id,
            week_start: @week_start,
            image_url: url
          })

        g
      end

      {:ok, first} =
        Mehungry.Posts.create_weekly_plan_post(make_graphic.("https://ex.com/1.png"), "Week",
          published_meal_plan_id: plan.id
        )

      {:ok, second} =
        Mehungry.Posts.create_weekly_plan_post(make_graphic.("https://ex.com/2.png"), "Week",
          published_meal_plan_id: plan.id
        )

      remaining =
        Mehungry.Repo.all(
          from(p in Mehungry.Posts.Post,
            where: p.type_ == "WEEKLY_PLAN" and p.published_meal_plan_id == ^plan.id,
            select: p.id
          )
        )

      assert remaining == [second.id]
      refute first.id in remaining
    end
  end

  # The test DB can already hold these USDA categories (from seeds or a prior
  # interrupted run), and `categories.name` is unique — so creating them outright
  # collides. Fetch-or-create keeps these tests independent of seed state.
  defp ensure_category(name) do
    case Mehungry.Food.get_category_by_name(name) do
      nil ->
        {:ok, category} = Mehungry.Food.create_category(%{name: name})
        category

      category ->
        category
    end
  end
end
