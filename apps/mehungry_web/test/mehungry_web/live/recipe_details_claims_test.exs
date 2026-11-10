defmodule MehungryWeb.RecipeDetailsClaimsTest do
  @moduledoc """
  The "Claims & reference intakes" panel on the recipe detail
  (`RecipeDetailsComponent`) — collapsed to the strongest 6 claims behind a
  "Show all" toggle. See `docs/implementation/food/nutrient_badges.md`.
  """
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.Repo

  # Badges are normally written async by RecipePutNutrientsWorker; set directly.
  # Descending %NRV so the collapsed cut is deterministic: the first 6 stay.
  @badges [
    %{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 90},
    %{"nutrient" => "Calcium", "level" => "high", "percent_nrv" => 80},
    %{"nutrient" => "Zinc", "level" => "high", "percent_nrv" => 70},
    %{"nutrient" => "Magnesium", "level" => "high", "percent_nrv" => 60},
    %{"nutrient" => "Potassium", "level" => "high", "percent_nrv" => 50},
    %{"nutrient" => "Selenium", "level" => "high", "percent_nrv" => 40},
    %{"nutrient" => "Copper", "level" => "source", "percent_nrv" => 20},
    %{"nutrient" => "Manganese", "level" => "source", "percent_nrv" => 16}
  ]

  defp recipe_with_badges(badges) do
    user = user_fixture()

    user
    |> recipe_fixture(%{image_url: "https://img/#{System.unique_integer()}.jpg"})
    |> Ecto.Changeset.change(%{badges: badges})
    |> Repo.update!()
  end

  test "collapses to the 6 strongest claims with a Show-all toggle", %{conn: conn} do
    recipe = recipe_with_badges(@badges)

    {:ok, view, html} = live(conn, ~p"/browse/#{recipe.id}")

    assert html =~ "Claims &amp; reference intakes"
    assert html =~ "Selenium"
    refute html =~ "Copper"
    refute html =~ "Manganese"
    assert html =~ "Show all 8 claims"

    expanded = view |> element("button[phx-click='toggle_claims']") |> render_click()

    assert expanded =~ "Copper"
    assert expanded =~ "Manganese"
    assert expanded =~ "Show fewer"

    collapsed = view |> element("button[phx-click='toggle_claims']") |> render_click()

    refute collapsed =~ "Copper"
    assert collapsed =~ "Show all 8 claims"
  end

  test "6 or fewer claims render in full with no toggle", %{conn: conn} do
    recipe = recipe_with_badges(Enum.take(@badges, 3))

    {:ok, _view, html} = live(conn, ~p"/browse/#{recipe.id}")

    assert html =~ "Zinc"
    refute html =~ "Show all"
  end
end
