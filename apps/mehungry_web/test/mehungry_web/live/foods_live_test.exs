defmodule MehungryWeb.FoodsLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.Literature

  setup do
    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, _} =
      Food.upsert_species_relationship(%{
        foundemental_species_id: species.id,
        compound_id: oxalate.id,
        relationship_type: "high_in",
        source: "literature"
      })

    {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})

    {:ok, _} =
      Health.add_recommendation(kidney.id, oxalate.id, %{
        recommendation: "avoid",
        severity: "high",
        source: "guideline"
      })

    {:ok, study} = Literature.upsert_study(%{pmid: 777_777, title: "Spinach oxalate content"})

    {:ok, _} =
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: spinach.id,
        search_term: "spinach oxalate"
      })

    %{species: species}
  end

  describe "/foods (species browse)" do
    test "lists species and links to the detail page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/foods")
      assert html =~ "Spinach"
      assert html =~ "/foods/Spinach"
    end
  end

  describe "/foods/:slug (species detail)" do
    test "renders the species with its compounds, conditions and research", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/foods/Spinach")

      # Async sections (compounds / conditions / studies) resolve after mount.
      html = render_async(view)

      assert html =~ "Spinach"
      assert html =~ "Oxalate"
      assert html =~ "Kidney Stones"
      assert html =~ "Spinach oxalate content"
    end

    test "redirects unknown species back to /foods", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/foods"}}} = live(conn, ~p"/foods/no-such-thing")
    end
  end
end
