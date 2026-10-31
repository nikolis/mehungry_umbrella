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

    test "the compound multi-select filters to species containing the picked compound", %{
      conn: conn,
      vitc: vitc
    } do
      {:ok, view, _html} = live(conn, ~p"/foods")

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

    test "clearing filters restores the full list", %{conn: conn, vitc: vitc} do
      {:ok, view, _html} = live(conn, ~p"/foods")

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
    test "renders the species with its compounds", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/foods/Spinach")

      # The compounds section resolves asynchronously after mount.
      html = render_async(view)

      assert html =~ "Spinach"
      assert html =~ "Oxalate"
    end

    test "redirects unknown species back to /foods", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/foods"}}} = live(conn, ~p"/foods/no-such-thing")
    end

    test "the synchronous dead render carries crawler-visible SEO + nutrition JSON-LD",
         %{conn: conn} do
      # The proof-engine page's whole point is organic search: the disconnected
      # ("dead") render Googlebot indexes must already carry the species name,
      # the SEO title, and the structured-data graph — not wait on assign_async.
      body = conn |> get(~p"/foods/Spinach") |> html_response(200)

      assert body =~ "Spinach"
      assert body =~ "Nutrition, Research &amp; Compounds"
      assert body =~ ~s("@type":"BreadcrumbList")
      assert body =~ ~s("@type":"NutritionInformation")
    end
  end
end
