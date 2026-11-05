defmodule MehungryWeb.CalendarIngredientMealSaveTest do
  @moduledoc """
  Regression test for saving an ingredient-only meal from the calendar.

  The unit picker (`MehungryWeb.SelectComponent`) used to derive its submitted
  hidden `<input>` value via `Map.put(assigns, :hidden_value, …)` inside
  `render/1`. A `Map.put` assign is invisible to LiveView change tracking, so
  after the first render the diff never patched the hidden input's `value` — the
  user's chosen measurement unit never reached the submitted form and the meal
  silently failed to save (`validate_unit_or_portion`). The value is now a
  change-tracked assign set in `update/2`; this test locks that in.
  """
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest
  import Ecto.Query

  setup [:register_and_log_in_user]

  test "new ingredient meal saves the picked ingredient + unit", %{conn: conn, user: user} do
    ingredient = ingredient_fixture()
    unit_selection = Mehungry.Food.ingredient_unit_options(ingredient.id, "en") |> hd() |> Map.fetch!(:unit_selection)
    date = Date.utc_today() |> Date.to_iso8601()

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"viewport" => %{"width" => 1200}})
      |> live(~p"/calendar/#{date}/Breakfast")

    view |> element("button[phx-value-mode='ingredient']") |> render_click()

    # The ingredient picker's select_function -> send_update to the meal form.
    Phoenix.LiveView.send_update(
      view.pid,
      MehungryWeb.CalendarLive.MealFormComponent,
      %{id: :new, ingredient_selected: {0, ingredient.id}}
    )

    _ = render(view)

    # The unit SelectComponent's JS hook writes its hidden input and fires a
    # phx-change="validate"; simulate that round-trip with the full form params.
    view
    |> form("form[phx-submit='submit']")
    |> render_change(%{
      "user_meal" => %{
        "ingredient_user_meals" => %{
          "0" => %{
            "ingredient_id" => Integer.to_string(ingredient.id),
            "quantity" => "100",
            "unit_selection" => Integer.to_string(unit_selection),
            "delete" => "false"
          }
        }
      }
    })

    html = render(view)

    # The change-tracking fix: the hidden input must now reflect the chosen unit
    # (it used to be stuck at its first-render "" value).
    assert [_, captured] =
             Regex.run(
               ~r/name="user_meal\[ingredient_user_meals\]\[0\]\[unit_selection\]"[^>]*value="([^"]*)"/,
               html
             )

    assert captured == Integer.to_string(unit_selection)

    # Submit as the browser serializes it (from the DOM) and confirm the row saved.
    view |> form("form[phx-submit='submit']") |> render_submit()

    meals =
      Mehungry.Repo.all(from m in Mehungry.History.UserMeal, where: m.user_id == ^user.id)
      |> Mehungry.Repo.preload(:ingredient_user_meals)

    assert [meal] = meals
    assert [row] = meal.ingredient_user_meals
    assert row.ingredient_id == ingredient.id
    assert row.measurement_unit_id == unit_selection
    assert row.quantity == 100.0
  end
end
