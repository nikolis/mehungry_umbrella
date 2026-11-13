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

    test "the dead render carries a crawlable A–Z directory linking every food", %{conn: conn} do
      # The paginated feed only renders page 1 on the dead render, so the A–Z
      # directory is what gives the long tail of food pages their link equity.
      body = conn |> get(~p"/foods") |> html_response(200)

      assert body =~ "Browse all foods A–Z"
      # A real, canonical-form anchor to the detail page (not a LiveView patch).
      assert body =~ ~s(href="/en/foods/Spinach")
    end
  end

  describe "/foods/:slug (species detail)" do
    test "renders the connected species page (async sidecars resolve without error)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/foods/Spinach")

      # The research/recipes sidecars resolve asynchronously after mount.
      html = render_async(view)

      assert html =~ "Spinach"
    end

    test "serves a real 404 for an unknown species (never a soft-404 redirect)", %{conn: conn} do
      # Intentional SEO decision in SpeciesDetailLive.Index.mount/3: a dead
      # /foods/:slug must 404, not 302 to /foods, so crawlers don't suppress
      # the whole species URL pattern.
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/foods/no-such-thing") end
    end

    test "the synchronous dead render carries crawler-visible SEO + nutrition JSON-LD",
         %{conn: conn} do
      # The proof-engine page's whole point is organic search: the disconnected
      # ("dead") render Googlebot indexes must already carry the species name,
      # the SEO title, and the structured-data graph — not wait on assign_async.
      body = conn |> get(~p"/foods/Spinach") |> html_response(200)

      assert body =~ "Spinach"
      # Title leads with the nutrient-query intent the GSC data shows.
      assert body =~ "Spinach Calories &amp; Nutrition Facts (per 100g)"
      assert body =~ ~s("@type":"BreadcrumbList")
      assert body =~ ~s("@type":"NutritionInformation")
    end

    test "the dead render consolidates every slug/locale variant onto one canonical per locale",
         %{conn: conn} do
      # A food is reachable at several URLs (bare /foods/Spinach, /en/…, /el/…,
      # and any translated slug). Each must declare the SAME reciprocal canonical
      # + hreflang pair so Google folds them into one page instead of splitting
      # the ranking signal (the Κάρδαμο → Cress duplicate-canonical fold).
      for url <- ["/foods/Spinach", "/en/foods/Spinach", "/el/foods/Spinach"] do
        body = conn |> get(url) |> html_response(200)

        assert body =~
                 ~s(<link rel="alternate" hreflang="en" href="https://www.m3hungry.com/en/foods/Spinach">)

        assert body =~
                 ~s(<link rel="alternate" hreflang="el" href="https://www.m3hungry.com/el/foods/Spinach">)
      end

      # Bare + English URL canonicalize to the English-locale URL; the Greek URL
      # canonicalizes within its own locale (never cross-canonicals to English).
      assert conn |> get("/foods/Spinach") |> html_response(200) =~
               ~s(<link rel="canonical" href="https://www.m3hungry.com/en/foods/Spinach">)

      assert conn |> get("/el/foods/Spinach") |> html_response(200) =~
               ~s(<link rel="canonical" href="https://www.m3hungry.com/el/foods/Spinach">)
    end
  end
end
