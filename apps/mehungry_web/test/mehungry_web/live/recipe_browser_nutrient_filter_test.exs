defmodule MehungryWeb.RecipeBrowserNutrientFilterTest do
  @moduledoc """
  The crawlable nutrient-claim filter surface (`/search/nutrient/:slug`) on the
  recipe browser — see `docs/implementation/food/nutrient_badges.md`.
  """
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.Repo

  # A public recipe carrying a persisted high-iron badge (badges are normally
  # written async by RecipePutNutrientsWorker; set directly here).
  defp high_iron_recipe(title) do
    user = user_fixture()

    recipe =
      recipe_fixture(user, %{title: title, image_url: "https://img/#{System.unique_integer()}.jpg"})

    recipe
    |> Ecto.Changeset.change(%{
      badges: [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}]
    })
    |> Repo.update!()
  end

  test "GET /search/nutrient/iron lists high-iron recipes with a neutral title", %{conn: conn} do
    recipe = high_iron_recipe("Iron Skillet Lentils")

    {:ok, view, html} = live(conn, ~p"/search/nutrient/iron")

    assert html =~ recipe.title
    assert page_title(view) =~ "High-Iron Recipes"
  end

  test "the chip rail renders crawlable nutrient links", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/browse")

    assert html =~ "/search/nutrient/iron"
    assert html =~ "/search/nutrient/calcium"
    assert html =~ "/search/nutrient/vitamin-c"
  end

  test "an unknown nutrient slug falls back to the default feed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search/nutrient/unobtainium")

    assert page_title(view) =~ "Browse Recipes"
  end
end
