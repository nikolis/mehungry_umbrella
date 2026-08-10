defmodule MehungryWeb.CalendarLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.History

  describe "Caledar Operations Test" do
    setup [:register_and_log_in_user]

    test "Recipe User Meals with current date show in page", %{conn: conn, user: user} do
      recipe1 = recipe_fixture(user)
      _recipe2 = recipe_fixture(user)
      from = NaiveDateTime.utc_now()
      to = NaiveDateTime.utc_now()

      recipe_user_meal_params =
        %{
          start_dt: from,
          end_dt: to,
          user_id: user.id,
          title: "The title",
          recipe_user_meals: [
            %{recipe_id: recipe1.id, consume_portions: 5, cooking: true, cooking_portions: 10}
          ]
        }

      {:ok, _user_meal} = History.create_user_meal(recipe_user_meal_params)

      # A viewport width is needed so the widget renders its calendar (rather than
      # the loading placeholder shown while device_width is unknown).
      {:ok, _index_live, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      # The current day has a meal, so its precomputed summary must render both
      # the accordion header tags and the daily summary card.
      assert html =~ "Daily Summary"
      assert html =~ "protein"
    end

    test "View recipe button opens the recipe details modal", %{conn: conn, user: user} do
      recipe = recipe_fixture(user)
      now = NaiveDateTime.utc_now()

      {:ok, _user_meal} =
        History.create_user_meal(%{
          start_dt: now,
          end_dt: now,
          user_id: user.id,
          title: "The title",
          recipe_user_meals: [
            %{recipe_id: recipe.id, consume_portions: 5, cooking_portions: 10}
          ]
        })

      {:ok, index_live, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      assert html =~ "View recipe"

      index_live
      |> element("button[phx-value-recipe_id='#{recipe.id}']", "View recipe")
      |> render_click()

      assert_patched(index_live, ~p"/calendar/recipe/#{recipe.id}")
      assert render(index_live) =~ "recipe_details_component"
      assert render(index_live) =~ recipe.title
    end

    test "day meals are grouped into per-type sections plus a combined Daily Summary",
         %{conn: conn, user: user} do
      recipe = recipe_fixture(user)
      now = NaiveDateTime.utc_now()

      for {title, meal_type} <- [
            {"Morning oats", "breakfast"},
            {"Steak night", "dinner"},
            {"Random bite", nil}
          ] do
        {:ok, _} =
          History.create_user_meal(%{
            start_dt: now,
            end_dt: now,
            user_id: user.id,
            title: title,
            meal_type: meal_type,
            recipe_user_meals: [
              %{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 2}
            ]
          })
      end

      # Rendering with duplicate DOM ids would crash the LiveView, so a clean
      # render here also guards id_key uniqueness across the per-type cards.
      {:ok, _index_live, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      # Per-type section headers + their own summary cards, ordered with unsorted last.
      assert html =~ "Breakfast Summary"
      assert html =~ "Dinner Summary"
      assert html =~ "Unsorted Summary"
      # The combined day roll-up is still present below the sections.
      assert html =~ "Daily Summary"

      # Each meal type is a collapsible accordion: its details body is hidden by
      # default and only the header button (with the toggle) is expanded on tap.
      today = Date.utc_today() |> Date.to_string()

      assert html =~ ~s(id="meal-type-#{today}-breakfast-body" class="hidden)
      assert html =~ ~s(id="meal-type-#{today}-dinner-body" class="hidden)
      assert html =~ ~s(id="meal-type-#{today}-unsorted-body" class="hidden)
    end

    test "the meal-type picker updates the form's meal_type", %{conn: conn} do
      today = Date.utc_today() |> Date.to_iso8601()

      {:ok, index_live, _html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar/#{today}/New meal")

      # Picking Breakfast sets the hidden meal_type input the changeset submits.
      # (Persistence of meal_type is covered in Mehungry.HistoryTest; the recipe
      # SelectComponent can't be driven through a plain form submit here.)
      html =
        index_live
        |> element("button[phx-value-meal_type='breakfast']", "Breakfast")
        |> render_click()

      assert html =~ ~s(name="user_meal[meal_type]")
      assert html =~ ~s(id="user_meal_meal_type" value="breakfast")

      # Switching to Unsorted clears it back to the nil/unsorted bucket.
      html =
        index_live
        |> element("button[phx-value-meal_type='unsorted']", "Unsorted")
        |> render_click()

      refute html =~ ~s(id="user_meal_meal_type" value="breakfast")
    end

    test "another user cannot open a foreign meal for editing", %{conn: conn} do
      other = Mehungry.AccountsFixtures.user_fixture()
      recipe = recipe_fixture(other)

      {:ok, foreign_meal} =
        History.create_user_meal(%{
          start_dt: NaiveDateTime.utc_now(),
          user_id: other.id,
          title: "Foreign meal",
          recipe_user_meals: [
            %{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}
          ]
        })

      # The edit route loads the meal scoped by the current user, so a foreign
      # meal id must not resolve (IDOR guard).
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/calendar/#{foreign_meal.id}")
      end
    end
  end
end
