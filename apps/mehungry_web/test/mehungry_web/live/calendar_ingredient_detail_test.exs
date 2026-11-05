defmodule MehungryWeb.CalendarIngredientDetailTest do
  @moduledoc """
  Covers the calendar "View ingredient" detail modal: a logged ingredient entry
  opens its own detail screen (the ingredient-side mirror of "View recipe"),
  leading with the as-logged amount and toggling to the per-100g reference.
  """
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest
  import Ecto.Query

  setup [:register_and_log_in_user]

  defp log_ingredient_meal(conn, ingredient) do
    unit_selection =
      Mehungry.Food.ingredient_unit_options(ingredient.id, "en") |> hd() |> Map.fetch!(:unit_selection)

    date = Date.utc_today() |> Date.to_iso8601()

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"viewport" => %{"width" => 1200}})
      |> live(~p"/calendar/#{date}/Breakfast")

    view |> element("button[phx-value-mode='ingredient']") |> render_click()

    Phoenix.LiveView.send_update(
      view.pid,
      MehungryWeb.CalendarLive.MealFormComponent,
      %{id: :new, ingredient_selected: {0, ingredient.id}}
    )

    _ = render(view)

    view
    |> form("form[phx-submit='submit']")
    |> render_change(%{
      "user_meal" => %{
        "ingredient_user_meals" => %{
          "0" => %{
            "ingredient_id" => Integer.to_string(ingredient.id),
            "quantity" => "200",
            "unit_selection" => Integer.to_string(unit_selection),
            "delete" => "false"
          }
        }
      }
    })

    view |> form("form[phx-submit='submit']") |> render_submit()

    Mehungry.Repo.one(from ium in Mehungry.History.IngredientUserMeal, limit: 1)
  end

  test "the detail modal opens for a logged ingredient and toggles nutrition basis",
       %{conn: conn} do
    ingredient = ingredient_fixture()
    ium = log_ingredient_meal(conn, ingredient)

    {:ok, view, html} = live(conn, ~p"/calendar/ingredient/#{ium.id}")

    # Leads with the ingredient identity + the as-logged amount.
    assert html =~ ingredient.name
    assert html =~ "As logged"
    assert html =~ "200"

    # Both bases are offered; as-logged is the default (active segment).
    assert has_element?(view, "button[phx-value-basis='as_logged']")
    assert has_element?(view, "button[phx-value-basis='per_100g']")

    # Toggling to per-100g flips the active segment (cheap flag, both trees loaded).
    per100 =
      view
      |> element("button[phx-value-basis='per_100g']")
      |> render_click()

    assert per100 =~ "Per 100 g"
  end
end
