defmodule MehungryWeb.HealthLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.{Food, Health}

  # Kidney Stones → avoid → Oxalate (advice layer), and Spinach high_in Oxalate
  # (food-facts layer) — so the derived "foods to be mindful of" read resolves
  # spinach through the shared compound.
  defp seed_condition(_ctx) do
    {:ok, kidney} = Health.create_condition(%{name: "Kidney Stones", category: "renal"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, _} =
      Health.add_recommendation(kidney.id, oxalate.id, %{
        recommendation: "avoid",
        severity: "high",
        evidence_level: "strong",
        source: "guideline"
      })

    # Species-facts layer: Spinach species high_in Oxalate, with spinach curated onto
    # it — the condition's "foods to be mindful of" derive strictly through the species.
    spinach = ingredient_fixture(%{name: "spinach"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    {:ok, _} =
      Food.upsert_species_relationship(%{
        foundemental_species_id: species.id,
        compound_id: oxalate.id,
        relationship_type: "high_in",
        source: "literature"
      })

    %{condition: kidney, compound: oxalate, ingredient: spinach}
  end

  describe "list page (guest)" do
    setup :seed_condition

    test "renders conditions without login", %{conn: conn, condition: condition} do
      {:ok, _view, html} = live(conn, ~p"/conditions")

      assert html =~ condition.name
      assert html =~ "renal"
    end

    test "empty state when there are no conditions", %{conn: conn} do
      # Wipe the seeded condition to exercise the empty branch.
      Mehungry.Repo.delete_all(Mehungry.Health.CompoundRecommendation)
      Mehungry.Repo.delete_all(Mehungry.Health.Condition)

      {:ok, _view, html} = live(conn, ~p"/conditions")
      assert html =~ "No health conditions have been added yet."
    end
  end

  describe "list page (logged in)" do
    setup [:register_and_log_in_user, :seed_condition]

    test "renders conditions for an authenticated user", %{conn: conn, condition: condition} do
      {:ok, _view, html} = live(conn, ~p"/conditions")
      assert html =~ condition.name
    end
  end

  describe "detail page" do
    setup :seed_condition

    test "renders recommendations and the derived foods", %{conn: conn, condition: condition} do
      {:ok, view, _html} = live(conn, ~p"/conditions/#{condition.id}")

      # Recommendations + derived foods load via assign_async.
      html = render_async(view)

      assert html =~ "Kidney Stones"
      assert html =~ "Dietary Recommendations"
      assert html =~ "Avoid"
      assert html =~ "Oxalate"
      # The recommendation references a compound; the Spinach species is derived
      # at read time (its scientific name shown too).
      assert html =~ "Foods to Be Mindful Of"
      assert html =~ "Spinach"
      assert html =~ "Spinacia oleracea"

      assert page_title(view) =~ "Kidney Stones"
    end

    test "redirects to /conditions for an unknown id", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/conditions"}}} =
               live(conn, ~p"/conditions/#{0}")
    end

    test "encouraged foods are split out and open a preview modal", %{
      conn: conn,
      condition: condition
    } do
      # Encourage layer: Folate is encouraged for the condition, and Kale contains it.
      {:ok, folate} = Food.upsert_compound(%{name: "Folate", compound_type: "other"})

      {:ok, _} =
        Health.add_recommendation(condition.id, folate.id, %{
          recommendation: "encourage",
          severity: "low",
          evidence_level: "moderate",
          source: "guideline"
        })

      kale = ingredient_fixture(%{name: "kale"})

      {:ok, kale_species} =
        Food.create_foundemental_species(%{
          "name" => "Kale",
          "scientific_name" => "Brassica oleracea"
        })

      {:ok, _} = Food.assign_foundemental_ingredient(kale_species.id, kale.id, "kale")

      {:ok, _} =
        Food.upsert_species_relationship(%{
          foundemental_species_id: kale_species.id,
          compound_id: folate.id,
          relationship_type: "contains",
          source: "literature"
        })

      {:ok, view, _html} = live(conn, ~p"/conditions/#{condition.id}")
      html = render_async(view)

      # Kale surfaces under its own "Encouraged Foods" section (not "Mindful Of").
      assert html =~ "Encouraged Foods"
      assert html =~ "Kale"

      # The Details link patches to :show_food and opens the preview modal.
      html =
        view
        |> element(~s{a[href="/conditions/#{condition.id}/food/#{kale_species.id}"]})
        |> render_click()

      assert html =~ "encouraged-food-modal"
      assert html =~ "Brassica oleracea"
      assert html =~ "View full food page"
      assert html =~ "/foods/Kale"

      # Drain the modal's assign_async tasks before the test tears down its
      # sandbox connection (otherwise the still-running query races teardown).
      render_async(view)
    end
  end

  describe "detail page (logged in)" do
    setup [:register_and_log_in_user, :seed_condition]

    test "a sample recipe can be saved for later from the modal", %{
      conn: conn,
      condition: condition,
      user: user
    } do
      # Encouraged food (Kale) plus a recipe that uses it, so a sample recipe shows.
      {:ok, folate} = Food.upsert_compound(%{name: "Folate", compound_type: "other"})

      {:ok, _} =
        Health.add_recommendation(condition.id, folate.id, %{
          recommendation: "encourage",
          severity: "low",
          evidence_level: "moderate",
          source: "guideline"
        })

      kale = ingredient_fixture(%{name: "kale"})

      {:ok, kale_species} =
        Food.create_foundemental_species(%{"name" => "Kale", "scientific_name" => "Brassica"})

      {:ok, _} = Food.assign_foundemental_ingredient(kale_species.id, kale.id, "kale")

      {:ok, _} =
        Food.upsert_species_relationship(%{
          foundemental_species_id: kale_species.id,
          compound_id: folate.id,
          relationship_type: "contains",
          source: "literature"
        })

      mu = measurement_unit_fixture()

      # A recipe by someone else (savable) and one the user authored (not savable).
      other_user = Mehungry.AccountsFixtures.user_fixture()

      recipe =
        recipe_fixture(other_user, %{
          title: "Kale Salad",
          recipe_ingredients: [%{ingredient_id: kale.id, measurement_unit_id: mu.id, quantity: 5}]
        })

      own_recipe =
        recipe_fixture(user, %{
          title: "My Kale Dish",
          recipe_ingredients: [%{ingredient_id: kale.id, measurement_unit_id: mu.id, quantity: 5}]
        })

      # Open the modal directly on the encouraged food.
      {:ok, view, _html} = live(conn, ~p"/conditions/#{condition.id}/food/#{kale_species.id}")
      html = render_async(view)

      assert html =~ "Kale Salad"
      assert html =~ "save-modal-recipe-#{recipe.id}"
      # The user's own recipe shows, but without a save button.
      assert html =~ "My Kale Dish"
      refute html =~ "save-modal-recipe-#{own_recipe.id}"
      refute recipe.id in Mehungry.Accounts.UserContent.list_user_saved_recipe_ids(user)

      # Clicking the heart saves the other user's recipe for later.
      view |> element("#save-modal-recipe-#{recipe.id}") |> render_click()

      assert recipe.id in Mehungry.Accounts.UserContent.list_user_saved_recipe_ids(user)
    end
  end
end
