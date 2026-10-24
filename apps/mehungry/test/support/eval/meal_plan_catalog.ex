defmodule Mehungry.AI.Eval.MealPlanCatalog do
  @moduledoc """
  Seeds a small, representative **fixture catalog** for the meal-plan eval
  harness: one owner user, a spread of slot- and cuisine-tagged recipes (each
  with real per-serving nutrition), a set of whole-food snack ingredients (also
  with nutrition), and two blueprints (a plain one and a Low-FODMAP one with an
  avoid list). Returns a `context` map ready to hand to the real `MealPlanAgent`
  and to `MealPlanScorer.score/2`.

  Realism notes (Layer 1):

    * Nutrition is wired: each recipe carries one nutrient-dense base ingredient
      at 100 g with slot-appropriate per-100g macros (`servings: 1`, so a meal
      contributes the full recipe), and each snack ingredient carries its own
      per-100g macros. This populates `recipe.nutrients` and the denormalized
      `ingredient_user_meals.nutrients`, so the eval can aggregate per-day macros
      through the app's own calendar path and the scorer's `calorie_fit` check
      becomes live (target in `:daily_calorie_target`).
    * Each recipe is seeded with a pgvector embedding (`EmbeddingClientStub`) so
      `search_catalog` runs the real vector-search path deterministically. The
      test env has no OpenAI key, and the strict full-text fallback misses the
      agent's natural-language queries (`plainto_tsquery` ANDs every term, and
      `vegetarian`→`no-meat` normalization drops matches) — which is why recipes
      never surfaced before.
  """

  import Ecto.Query
  alias Mehungry.{Food, Repo}
  alias Mehungry.Food.{IngredientNutrient, MeasurementUnit, Nutrient, Recipe}
  alias Mehungry.MealBlueprints.Blueprint
  alias Mehungry.AI.EmbeddingClientStub
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2, ingredient_fixture: 1]
  import Mehungry.AccountsFixtures, only: [user_fixture: 1]

  @daily_calorie_target 2000

  # Descriptive titles so the stubbed embedding ranks recipes by lexical overlap
  # with the agent's slot queries ("light breakfast", "hearty mediterranean
  # dinner", …). One garlic dish is deliberate bait for the Low-FODMAP check.
  @recipes [
    "Greek Yogurt Breakfast Bowl with Honey",
    "Light Oatmeal Breakfast with Berries",
    "Spinach and Feta Breakfast Omelette",
    "Quick Avocado Toast Breakfast",
    "Mediterranean Quinoa Lunch Salad",
    "Grilled Chicken Caesar Lunch Wrap",
    "Lentil Soup Light Lunch",
    "Vegetarian Buddha Bowl Lunch",
    "Tuna and White Bean Lunch Salad",
    "Hearty Mediterranean Baked Salmon Dinner",
    "Slow Roasted Garlic Chicken Dinner",
    "Beef and Vegetable Stew Dinner",
    "Eggplant Parmesan Dinner",
    "Shrimp and Vegetable Stir Fry Dinner",
    "Moroccan Chickpea Tagine Dinner",
    "Mushroom Risotto Dinner"
  ]

  @ingredients ~w(Apple Banana Almonds Walnuts)a ++
                 ["Greek Yogurt", "Feta Cheese", "Carrot", "Orange", "Blueberries", "Cucumber"]

  # Per-100g macro profiles (energy kcal; protein/fat/sat/carbs g). A recipe's
  # base ingredient is exactly 100 g, so the recipe total equals its slot profile.
  # `sat` (a slice of `fat`) is required for the fat node to materialize — the
  # hierarchy builder only emits a Total Fat node when a fat subcategory exists.
  @breakfast %{energy: 400, protein: 20, fat: 12, sat: 4, carbs: 55}
  @lunch %{energy: 550, protein: 30, fat: 18, sat: 6, carbs: 62}
  @dinner %{energy: 700, protein: 40, fat: 25, sat: 9, carbs: 70}
  @snack %{energy: 250, protein: 8, fat: 12, sat: 3, carbs: 28}

  @doc """
  Seeds the catalog and returns a context map (user_id, start_date, recipes,
  ingredients, recipe_names, ingredient_names, daily_calorie_target, and the two
  blueprints). Options: `:start_date` (defaults to next Monday).
  """
  def seed(opts \\ []) do
    user = user_fixture(%{})
    start_date = Keyword.get(opts, :start_date, next_monday())
    nut = setup_nutrients()

    recipes =
      Enum.map(@recipes, fn title ->
        base = ingredient_fixture(%{name: "base for #{title}"})
        attach_nutrients(base.id, nut, profile_for(title))

        r =
          recipe_fixture(user, %{
            title: title,
            servings: 1,
            recipe_ingredients: [
              %{ingredient_id: base.id, measurement_unit_id: nut.gram_mu.id, quantity: 100}
            ]
          })

        seed_embedding(r.id, title)
        put_recipe_nutrients(r.id)
        %{id: r.id, title: title}
      end)

    ingredients =
      Enum.map(@ingredients, fn name ->
        name = to_string(name)
        i = ingredient_fixture(%{name: name})
        attach_nutrients(i.id, nut, @snack)
        %{id: i.id, name: name}
      end)

    %{
      user_id: user.id,
      start_date: start_date,
      daily_calorie_target: @daily_calorie_target,
      recipes: recipes,
      ingredients: ingredients,
      recipe_names: Map.new(recipes, &{&1.id, &1.title}),
      ingredient_names: Map.new(ingredients, &{&1.id, &1.name}),
      blueprint_plain: %Blueprint{
        name: "Balanced Week",
        description: "A balanced, varied Mediterranean week with light breakfasts and hearty dinners.",
        avoid_foods: []
      },
      blueprint_low_fodmap: %Blueprint{
        name: "Low-FODMAP (IBS)",
        description: "Low-FODMAP plan for IBS — no onion or garlic in any dish.",
        avoid_foods: ["onion", "garlic"]
      }
    }
  end

  # ── nutrition fixtures ──────────────────────────────────────────────────────

  # One shared set of canonical nutrient rows + the gram unit recipe ingredients
  # are measured in. Names/units match what the calc engine and `macro_summary`
  # key on (Energy in kcal; macros in grams, bucketed by name keyword).
  defp setup_nutrients do
    kcal = unit("kilocalorie")
    gram = unit("gram")

    %{
      gram_mu: gram,
      energy: nutrient("Energy", "1008", 1, kcal.id),
      protein: nutrient("Protein", "203", 2, gram.id),
      fat: nutrient("Total Fat", "204", 3, gram.id),
      sat_fat: nutrient("Saturated Fat", "606", 5, gram.id),
      carbs: nutrient("Carbohydrate, by difference", "205", 4, gram.id)
    }
  end

  # Names are globally unique (`measurement_units_name_index` / nutrients'
  # `[:name, :measurement_unit_id]`), and base units may already exist — so
  # fetch-or-create rather than blindly insert.
  defp unit(name) do
    Repo.get_by(MeasurementUnit, name: name) || Repo.insert!(%MeasurementUnit{name: name})
  end

  defp nutrient(name, number, rank, mu_id) do
    Repo.get_by(Nutrient, name: name, measurement_unit_id: mu_id) ||
      Repo.insert!(%Nutrient{name: name, number: number, rank: rank, measurement_unit_id: mu_id})
  end

  defp attach_nutrients(ingredient_id, nut, %{energy: e, protein: p, fat: f, sat: s, carbs: c}) do
    for {nutrient, amount} <- [
          {nut.energy, e},
          {nut.protein, p},
          {nut.fat, f},
          {nut.sat_fat, s},
          {nut.carbs, c}
        ] do
      Repo.insert!(%IngredientNutrient{
        ingredient_id: ingredient_id,
        nutrient_id: nutrient.id,
        amount: amount * 1.0
      })
    end
  end

  defp profile_for(title) do
    cond do
      String.contains?(title, "Breakfast") -> @breakfast
      String.contains?(title, "Lunch") -> @lunch
      true -> @dinner
    end
  end

  # Compute and persist `recipe.nutrients` synchronously (create_recipe only
  # enqueues this via Oban, which is manual in tests). Mirrors the core of
  # RecipePutNutrientsWorker without its Posts/Cachex side effects.
  defp put_recipe_nutrients(recipe_id) do
    recipe =
      Recipe
      |> Repo.get!(recipe_id)
      |> Repo.preload(recipe_ingredients: [:measurement_unit, :ingredient, :ingredient_portion])

    recipe
    |> Food.change_recipe()
    |> Food.put_nutrient_info(Map.from_struct(recipe))
    |> Repo.update!()
  end

  # ── embeddings ──────────────────────────────────────────────────────────────

  # Seed the recipe's pgvector embedding from the same hashing function the
  # stubbed embedding client uses for queries, so `RecipeVectorSearch` (the real
  # vector path, via the `:embedding_client` test seam) ranks recipes by lexical
  # overlap with the agent's natural-language queries.
  defp seed_embedding(recipe_id, title) do
    vector = Pgvector.new(EmbeddingClientStub.vector(title))
    Repo.update_all(from(r in Recipe, where: r.id == ^recipe_id), set: [embedding: vector])
  end

  defp next_monday do
    today = Date.utc_today()
    Date.add(today, rem(8 - Date.day_of_week(today), 7) |> then(&if(&1 == 0, do: 7, else: &1)))
  end
end
