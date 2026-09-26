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
        source: "guideline",
        source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
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

  describe "/foods filtering" do
    setup %{species: spinach_species} do
      # A second species with an *encouraged* compound for a condition.
      {:ok, apple} =
        Food.create_foundemental_species(%{
          "name" => "Apple",
          "scientific_name" => "Malus domestica"
        })

      {:ok, vitc} = Food.upsert_compound(%{name: "Vitamin C", compound_type: "other"})

      {:ok, _} =
        Food.upsert_species_relationship(%{
          foundemental_species_id: apple.id,
          compound_id: vitc.id,
          relationship_type: "high_in",
          source: "literature"
        })

      {:ok, scurvy} = Health.upsert_condition(%{name: "Scurvy", category: "nutrition"})

      {:ok, _} =
        Health.add_recommendation(scurvy.id, vitc.id, %{
          recommendation: "encourage",
          severity: "high",
          source: "guideline",
          source_reference: %{"label" => "Guideline", "url" => "https://example.org"}
        })

      %{apple: apple, vitc: vitc, scurvy: scurvy, spinach: spinach_species}
    end

    test "filtering by a condition keeps only species encouraged for it", %{
      conn: conn,
      scurvy: scurvy
    } do
      {:ok, view, _html} = live(conn, ~p"/foods")

      html =
        view
        |> element("button[phx-click='toggle_condition'][phx-value-id='#{scurvy.id}']")
        |> render_click()

      assert html =~ "Apple"
      refute html =~ "Spinach"
      assert html =~ "filtered species"
    end

    test "the compound multi-select filters to species containing the picked compound", %{
      conn: conn,
      vitc: vitc
    } do
      {:ok, view, _html} = live(conn, ~p"/foods")

      # Switch to compound mode, search, then pick the suggestion.
      render_click(element(view, "button[phx-value-mode='compound']"))

      html = render_change(element(view, "form[phx-change='search_compounds']"), %{"q" => "Vitamin"})
      assert html =~ "Vitamin C"

      html =
        view
        |> element("button[phx-click='add_compound'][phx-value-id='#{vitc.id}']")
        |> render_click()

      assert html =~ "Apple"
      refute html =~ "Spinach"
      assert html =~ "filtered species"
    end

    test "switching modes applies only the active mode's facet", %{
      conn: conn,
      scurvy: scurvy,
      vitc: vitc
    } do
      {:ok, view, _html} = live(conn, ~p"/foods")

      # Select a condition (condition mode is the default).
      render_click(
        element(view, "button[phx-click='toggle_condition'][phx-value-id='#{scurvy.id}']")
      )

      # Add a compound in compound mode.
      render_click(element(view, "button[phx-value-mode='compound']"))
      render_change(element(view, "form[phx-change='search_compounds']"), %{"q" => "Vitamin"})

      html =
        view
        |> element("button[phx-click='add_compound'][phx-value-id='#{vitc.id}']")
        |> render_click()

      # Only Apple carries Vitamin C — the earlier condition pick does not stack.
      assert html =~ "Apple"
      refute html =~ "Spinach"
    end

    test "clearing filters restores the full list", %{conn: conn, vitc: vitc} do
      {:ok, view, _html} = live(conn, ~p"/foods")

      render_click(element(view, "button[phx-value-mode='compound']"))
      render_change(element(view, "form[phx-change='search_compounds']"), %{"q" => "Vitamin"})
      render_click(element(view, "button[phx-click='add_compound'][phx-value-id='#{vitc.id}']"))

      html =
        view
        |> element("button[phx-click='clear_filters']")
        |> render_click()

      assert html =~ "Apple"
      assert html =~ "Spinach"
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
