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
      Food.create_foundemental_species(%{"name" => "Spinach", "scientific_name" => "Spinacia oleracea"})

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
  end
end
