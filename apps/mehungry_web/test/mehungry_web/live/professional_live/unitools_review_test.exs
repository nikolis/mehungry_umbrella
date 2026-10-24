defmodule MehungryWeb.ProfessionalLive.UniToolsReviewTest do
  @moduledoc """
  Covers the admin UniTools review LiveView: the dataset picker, loading a decoded
  recipe into the form beside the verbatim dataset JSON, skipping (records +
  advances), resuming past reviewed recipes, the "all done" state, a failed load's
  retry state, and that save stamps source/licence/visibility. The dataset load is
  stubbed via `:unitools_client`.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.FoodData.UniTools.Imports

  @admin_email Application.compile_env(:mehungry, :admin_email)
  @dataset_id "v1"

  @dataset %{
    "name" => "UniTools World Recipes",
    "license" => "CC BY-SA 4.0",
    "attribution" => "UniTools — theunitools.com",
    "landingPage" => "https://theunitools.com/en/data",
    "countries" => [%{"code" => "IT", "cuisine" => %{"en" => "Italian cuisine"}}],
    "recipes" => [
      %{
        "country" => "IT",
        "name" => %{"en" => "Spaghetti carbonara"},
        "summary" => %{"en" => "Four ingredients."},
        "difficulty" => "medium",
        "baseServings" => 2,
        "prepMinutes" => 10,
        "cookMinutes" => 15,
        "ingredients" => [
          %{"name" => %{"en" => "Spaghetti"}, "quantity" => 200, "unit" => "g", "note" => nil}
        ],
        "steps" => [%{"text" => %{"en" => "Boil the water."}, "minutes" => 8}]
      },
      %{
        "country" => "IT",
        "name" => %{"en" => "Margherita pizza"},
        "summary" => %{"en" => "Tomato, mozzarella, basil."},
        "difficulty" => "hard",
        "baseServings" => 4,
        "prepMinutes" => 30,
        "cookMinutes" => 12,
        "ingredients" => [
          %{"name" => %{"en" => "Spaghetti"}, "quantity" => 300, "unit" => "g", "note" => nil}
        ],
        "steps" => [%{"text" => %{"en" => "Bake it hot."}, "minutes" => 12}]
      }
    ]
  }

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    Application.put_env(:mehungry, :unitools_client_datasets, %{@dataset_id => {:ok, @dataset}})

    # The resolver needs a gram unit + a matchable ingredient so the saved recipe
    # has ≥1 ingredient (required by the changeset).
    measurement_unit_fixture(%{name: "grams"})
    ingredient_fixture(%{name: "Spaghetti", food_class: "Foundation"})

    on_exit(fn -> Application.delete_env(:mehungry, :unitools_client_datasets) end)

    %{conn: conn}
  end

  test "the picker lists catalogued datasets", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/unitools-review")

    assert html =~ "UniTools import review"
    assert html =~ "UniTools World Recipes"
    assert html =~ "CC BY-SA 4.0"
    assert html =~ "Browse recipes"
  end

  test "opening a dataset shows the searchable recipe list (not a blind next)", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}")

    # Both decoded recipes are listed as choices.
    assert html =~ "Spaghetti carbonara"
    assert html =~ "Margherita pizza"
    # The search box is the primary way to pick a recipe.
    assert html =~ ~s(name="q")
  end

  test "fuzzy search filters the recipe list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}")

    html = view |> form("form[phx-change=search]", %{q: "margherita"}) |> render_change()

    assert html =~ "Margherita pizza"
    refute html =~ "Spaghetti carbonara"
  end

  test "a specific recipe can be opened by index into the review form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}/2")
    assert html =~ "Margherita pizza"
    assert html =~ "of 2"
  end

  test "skip records the recipe ref and returns to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}/1")

    html = view |> element("button", "Skip") |> render_click()

    assert Imports.status_for(Imports.ref(@dataset_id, 1)) == "skipped"
    # Back on the recipe list, where the skipped recipe is badged.
    assert html =~ "Spaghetti carbonara"
    assert html =~ "skipped"
  end

  test "the recipe list badges already-reviewed recipes", %{conn: conn} do
    Imports.mark_completed(Imports.ref(@dataset_id, 1), nil)

    {:ok, _view, html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}")

    assert html =~ "Spaghetti carbonara"
    assert html =~ "completed"
  end

  test "a failed dataset load shows a distinct retry state, not 'all caught up'", %{conn: conn} do
    Application.put_env(:mehungry, :unitools_client_datasets, %{@dataset_id => {:error, :enoent}})

    {:ok, _view, html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}")

    assert html =~ "load the dataset"
    assert html =~ "Retry"
    refute html =~ "All caught up"
  end

  test "saving stages the recipe private and tagged source=unitools with licence", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}/1")

    view |> form("#create-recipe-form") |> render_submit()

    assert [recipe] = saved_unitools_recipes()
    assert recipe.source == "unitools"
    assert recipe.license == "CC BY-SA 4.0"
    assert recipe.private == true
    assert recipe.original_url == "https://theunitools.com/en/data"
    assert Imports.status_for(Imports.ref(@dataset_id, 1)) == "completed"
  end

  test "ticking Publish saves the recipe public", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/unitools-review/#{@dataset_id}/1")

    view |> element("button", "Saving as private") |> render_click()
    view |> form("#create-recipe-form") |> render_submit()

    assert [recipe] = saved_unitools_recipes()
    assert recipe.private == false
    assert recipe.source == "unitools"
  end

  defp saved_unitools_recipes do
    import Ecto.Query
    Mehungry.Repo.all(from r in Mehungry.Food.Recipe, where: r.source == "unitools")
  end

  test "non-admins are redirected", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, _}} = live(conn, ~p"/professional/unitools-review")
  end
end
