defmodule MehungryWeb.ProfessionalLive.MyPlateReviewTest do
  @moduledoc """
  Covers the admin MyPlate review LiveView: loading a slug into the form beside
  the raw JSON, skipping (records + advances), resuming past already-reviewed
  slugs, and the "all done" state. The MyPlate API is stubbed via `:myplate_client`.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.FoodData.MyPlate.Imports

  @admin_email Application.compile_env(:mehungry, :admin_email)

  defp recipe_payload(name) do
    %{
      "name" => name,
      "yield" => "4 servings",
      "directions" => "Mix it. Bake it.",
      "image_url" => "https://img.example/#{name}.jpg",
      "source_url" => "https://www.myplate.gov/recipes/#{name}",
      "contributor" => "USDA",
      "ingredients" => [%{"text" => "1 cup olive oil", "note" => nil}]
    }
  end

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    # A small stubbed corpus.
    Application.put_env(:mehungry, :myplate_client_slugs, {:ok, ["alpha", "beta", "gamma"]})

    Application.put_env(:mehungry, :myplate_client_recipes, %{
      "alpha" => {:ok, recipe_payload("alpha")},
      "beta" => {:ok, recipe_payload("beta")},
      "gamma" => {:ok, recipe_payload("gamma")}
    })

    # The resolver needs a gram unit + an ingredient the lines can match.
    measurement_unit_fixture(%{name: "grams"})
    ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})

    on_exit(fn ->
      Application.delete_env(:mehungry, :myplate_client_slugs)
      Application.delete_env(:mehungry, :myplate_client_recipes)
    end)

    %{conn: conn}
  end

  test "the recipe list is the landing surface and is searchable (not a blind next)",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/myplate-review")

    assert html =~ "MyPlate import review"
    # Every slug is listed (humanized) as a choice.
    assert html =~ "Alpha"
    assert html =~ "Beta"
    assert html =~ "Gamma"
    # The search box is the primary way to pick a recipe.
    assert html =~ ~s(name="q")
    # The list must not blind-fetch a recipe (no raw JSON panel yet).
    refute html =~ "source_url"
  end

  test "fuzzy search filters the recipe list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/myplate-review")

    html = view |> form("form[phx-change=search]", %{q: "beta"}) |> render_change()

    assert html =~ "Beta"
    refute html =~ "Alpha"
    refute html =~ "Gamma"
  end

  test "a specific slug can be opened by URL into the review form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/myplate-review/beta")
    assert html =~ "beta"
    # Right panel is the ingredient reference (not raw JSON): source lines + steps.
    assert html =~ "Ingredients"
    assert html =~ "olive oil"
    assert html =~ "Steps"
    assert html =~ "Mix it."
    # The raw JSON dump is gone.
    refute html =~ "source_url"
  end

  test "unmatched source ingredients are badged in the right panel", %{conn: conn} do
    # "1 cup olive oil" has no matchable cup-portion in this fixture set, so it
    # resolves as unmatched and must be flagged for the admin to fix by hand.
    {:ok, _view, html} = live(conn, ~p"/professional/myplate-review/beta")

    assert html =~ "olive oil"
    assert html =~ "unmatched"
  end

  test "skip records the slug and returns to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/myplate-review/alpha")

    html = view |> element("button", "Skip") |> render_click()

    assert Imports.status_for("alpha") == "skipped"
    # Back on the recipe list, where the skipped slug is badged.
    assert html =~ "Alpha"
    assert html =~ "skipped"
  end

  test "the recipe list badges already-reviewed slugs", %{conn: conn} do
    Imports.mark_completed("alpha", nil)

    {:ok, _view, html} = live(conn, ~p"/professional/myplate-review")

    assert html =~ "Alpha"
    assert html =~ "completed"
  end

  test "a failed slug-list load shows a distinct retry state, not 'all caught up'", %{conn: conn} do
    # The myplate.food API is occasionally flaky; a failure must not masquerade
    # as "all reviewed".
    Application.put_env(:mehungry, :myplate_client_slugs, {:error, :timeout})

    {:ok, _view, html} = live(conn, ~p"/professional/myplate-review")

    # Distinct "couldn't load" state (note: the apostrophe renders HTML-escaped).
    assert html =~ "load the MyPlate list"
    assert html =~ "Retry"
    refute html =~ "All caught up"
    # The editable form is not shown when the list failed to load.
    refute html =~ "create-recipe-form"
  end

  test "the daily full-recipe cap (429) is shown as a distinct rate-limited state", %{conn: conn} do
    # myplate.food caps full-recipe fetches at 100/day/IP; the client surfaces
    # that as {:rate_limited, seconds} and the UI explains it (not a blank form).
    Application.put_env(:mehungry, :myplate_client_recipes, %{
      "alpha" => {:error, {:rate_limited, 29_791}}
    })

    # The cap is only hit when a recipe is actually fetched (opened), not on the list.
    {:ok, _view, html} = live(conn, ~p"/professional/myplate-review/alpha")

    assert html =~ "Daily MyPlate limit reached"
    assert html =~ "100 per day"
    assert html =~ "~9h"
    refute html =~ "create-recipe-form"
  end

  test "non-admins are redirected", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, _}} = live(conn, ~p"/professional/myplate-review")
  end
end
