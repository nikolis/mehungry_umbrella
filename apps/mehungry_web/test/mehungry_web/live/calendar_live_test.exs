defmodule MehungryWeb.CalendarLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.History
  alias Mehungry.MealBlueprints

  describe "Day notes" do
    setup [:register_and_log_in_user]

    test "saving a day note persists it and it re-renders on reload", %{conn: conn, user: user} do
      date = Date.utc_today()
      iso = Date.to_iso8601(date)

      {:ok, view, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      # The private day-note field is present for the user's own calendar.
      assert html =~ "Day note"

      view
      |> form("#day-note-form-#{iso}", %{"body" => "felt bloated after lunch"})
      |> render_submit()

      assert History.get_day_note(user.id, date).body == "felt bloated after lunch"

      # Reloading the calendar pre-fills the saved note.
      {:ok, _view2, html2} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      assert html2 =~ "felt bloated after lunch"
    end

    test "clearing a day note deletes it", %{conn: conn, user: user} do
      date = Date.utc_today()
      iso = Date.to_iso8601(date)
      {:ok, _} = History.upsert_day_note(user.id, date, "temporary")

      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      view
      |> form("#day-note-form-#{iso}", %{"body" => ""})
      |> render_submit()

      assert History.get_day_note(user.id, date) == nil
    end
  end

  describe "Copy meal to today" do
    setup [:register_and_log_in_user]

    test "duplicates a past meal onto today and it appears in the grid", %{
      conn: conn,
      user: user
    } do
      recipe = recipe_fixture(user, %{title: "Repeat Breakfast"})
      today = Date.utc_today()
      past = Date.add(today, -3)

      {:ok, _} =
        History.create_user_meal(%{
          start_dt: NaiveDateTime.new!(past, ~T[08:00:00]),
          end_dt: NaiveDateTime.new!(past, ~T[08:30:00]),
          user_id: user.id,
          title: "Repeat Breakfast",
          meal_type: "breakfast",
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
        })

      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar/ondate/#{Date.to_iso8601(past)}")

      before = History.list_calendar_user_meals(user.id, today, today) |> length()

      view
      |> element(~s|button[phx-click="copy_meal_to_today"]|)
      |> render_click()

      after_count = History.list_calendar_user_meals(user.id, today, today) |> length()
      assert after_count == before + 1
    end
  end

  describe "Foods I avoid" do
    setup [:register_and_log_in_user]

    test "flags a logged meal whose food name is on the avoid list", %{conn: conn, user: user} do
      recipe = recipe_fixture(user, %{title: "Onion Soup"})
      now = NaiveDateTime.utc_now()

      {:ok, _} =
        History.create_user_meal(%{
          start_dt: now,
          end_dt: now,
          user_id: user.id,
          title: "Lunch",
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
        })

      profile = Mehungry.Accounts.get_user_profile_by_user_id(user.id)
      {:ok, _} = Mehungry.Accounts.set_avoid_foods(profile, ["onion"])

      {:ok, _view, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      assert html =~ "On your avoid list"
    end

    test "a meal with no avoided food is not flagged", %{conn: conn, user: user} do
      recipe = recipe_fixture(user, %{title: "Tomato Salad"})
      now = NaiveDateTime.utc_now()

      {:ok, _} =
        History.create_user_meal(%{
          start_dt: now,
          end_dt: now,
          user_id: user.id,
          title: "Lunch",
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
        })

      profile = Mehungry.Accounts.get_user_profile_by_user_id(user.id)
      {:ok, _} = Mehungry.Accounts.set_avoid_foods(profile, ["onion"])

      {:ok, _view, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      refute html =~ "On your avoid list"
    end

    test "saving the avoid list from the calendar persists it", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      view
      |> form(~s|form[phx-submit="save_avoid_foods"]|, %{"foods" => "onion\ngarlic"})
      |> render_submit()

      assert Mehungry.Accounts.get_user_profile_by_user_id(user.id).avoid_foods == [
               "onion",
               "garlic"
             ]
    end
  end

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

    test "navigating to another week loads that week's meals from the DB", %{
      conn: conn,
      user: user
    } do
      near = recipe_fixture(user, %{title: "Near Week Dish"})
      far = recipe_fixture(user, %{title: "Far Week Dish"})

      now = NaiveDateTime.utc_now()
      far_dt = ~N[2026-07-15 12:00:00]

      {:ok, _} =
        History.create_user_meal(%{
          start_dt: now,
          end_dt: now,
          user_id: user.id,
          title: "Near",
          recipe_user_meals: [%{recipe_id: near.id, consume_portions: 1, cooking_portions: 1}]
        })

      {:ok, _} =
        History.create_user_meal(%{
          start_dt: far_dt,
          end_dt: far_dt,
          user_id: user.id,
          title: "Far",
          recipe_user_meals: [%{recipe_id: far.id, consume_portions: 1, cooking_portions: 1}]
        })

      {:ok, view, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      # Only the current week is loaded on mount.
      assert html =~ "Near Week Dish"
      refute html =~ "Far Week Dish"

      # Week navigation patches to /calendar/ondate/:date, which must reload that
      # week's meals (they were never loaded on mount).
      patched = render_patch(view, ~p"/calendar/ondate/2026-07-15")
      assert patched =~ "Far Week Dish"
      refute patched =~ "Near Week Dish"
    end

    test "an arbitrary free-food meal renders its card and counts in the day total",
         %{conn: conn, user: user} do
      now = NaiveDateTime.utc_now()

      {:ok, _user_meal} =
        History.create_user_meal(%{
          start_dt: now,
          end_dt: now,
          user_id: user.id,
          title: "Grabbed lunch",
          meal_type: "lunch",
          free_food_user_meals: [
            %{
              name: "Street Gyros",
              grams: 300.0,
              nutrients_per_100g: %{
                "Energy" => %{"unit" => "kcal", "amount" => 250},
                "Protein" => %{"unit" => "g", "amount" => 12}
              }
            }
          ]
        })

      {:ok, _index_live, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      # The free-food card renders (name + grams) and the day roll-up is present,
      # which means the entry flowed through the shared summariser.
      assert html =~ "Street Gyros"
      assert html =~ "300 g"
      assert html =~ "Daily Summary"
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

      # Per-type section headers, ordered with unsorted last. Each section is a
      # bare collapsible label (no per-type badges or summary card) — the
      # nutrition roll-up lives only in the combined Daily Summary below.
      assert html =~ "Breakfast"
      assert html =~ "Dinner"
      assert html =~ "Unsorted"
      refute html =~ "Breakfast Summary"
      refute html =~ "Dinner Summary"
      refute html =~ "Unsorted Summary"
      # The combined day roll-up is still present below the sections.
      assert html =~ "Daily Summary"

      # Each meal type is a collapsible accordion. The *current day* renders open
      # by default so today lands readable, so its section bodies are NOT hidden
      # and the toggle buttons report aria-expanded="true" (keyboard-operable).
      today = Date.utc_today() |> Date.to_string()

      refute html =~ ~s(id="meal-type-#{today}-breakfast-body" class="hidden)
      refute html =~ ~s(id="meal-type-#{today}-dinner-body" class="hidden)
      refute html =~ ~s(id="meal-type-#{today}-unsorted-body" class="hidden)
      assert html =~ ~s(aria-controls="meal-type-#{today}-breakfast-body")
    end

    test "current day lands expanded; other days collapse but show badges; headers are keyboard-operable",
         %{conn: conn, user: user} do
      recipe = recipe_fixture(user)
      today = Date.utc_today()
      week_start = Date.beginning_of_week(today)
      # A different day inside the same visible week as today.
      other = if today == week_start, do: Date.add(week_start, 1), else: week_start

      for {day, meal_type} <- [{today, "breakfast"}, {other, "lunch"}] do
        dt = NaiveDateTime.new!(day, ~T[12:00:00])

        {:ok, _} =
          History.create_user_meal(%{
            start_dt: dt,
            end_dt: dt,
            user_id: user.id,
            title: "Meal",
            meal_type: meal_type,
            recipe_user_meals: [
              %{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 2}
            ]
          })
      end

      {:ok, view, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar")

      today_s = Date.to_string(today)
      other_s = Date.to_string(other)

      # The current day renders open by default (container + chevron carry `copen`),
      # and its meal-type body is not hidden — today lands readable with zero taps.
      assert html =~ "day_of_week copen"
      assert html =~ ~s(class="size-5 widget_day copen")
      refute html =~ ~s(id="meal-type-#{today_s}-breakfast-body" class="hidden)

      # A non-current day stays collapsed: its section body keeps the `hidden` class.
      assert html =~ ~s(id="meal-type-#{other_s}-lunch-body")
      assert html =~ "p-2 sm:p-3 space-y-2 hidden"

      # Every day (not just today) now carries its at-a-glance header badge row —
      # the day-header tags render for the non-current day too.
      assert html =~ ~s(class="ml-auto flex flex-wrap gap-2 items-center justify-start")

      # Accordion headers are real buttons with aria state kept in sync client-side.
      assert html =~ ~s(aria-expanded="true")
      assert html =~ ~s(aria-expanded="false")
      assert html =~ ~s(aria-controls="daybody-#{today_s}")

      # The per-day "+" is a discoverable, labelled add control (no longer a hidden
      # click target on the day name), wired to open the add-meal flow for that day.
      assert html =~ "Add a meal on"
      assert has_element?(view, ~s(button[phx-click="pick-date"][phx-value-date="#{other_s}"]))
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

    test "arriving via 'Use this blueprint' shows the blueprint progress panel",
         %{conn: conn, user: user} do
      {:ok, bp} =
        MealBlueprints.create_blueprint(
          user.id
          |> MealBlueprints.default_blueprint_attrs("My week")
          |> Map.merge(%{
            visibility: "public",
            required_compounds: ["Flavonoid"],
            required_nutrients: ["Protein"],
            preferred_foods: ["Olive oil"]
          })
        )

      {:ok, index_live, html} =
        conn
        |> put_connect_params(%{"viewport" => %{"width" => 1200}})
        |> live(~p"/calendar?#{[blueprint_id: bp.id]}")

      assert html =~ "How your week measures up"
      assert html =~ "My week"
      # A required compound with no covering meal renders as an unmet goal.
      assert html =~ "Flavonoid"

      # Following a blueprint swaps the day header's nutrient totals for the
      # blueprint's Goals/Avoid targets, each nutrient chip carrying its current
      # measure vs. the threshold (here the default ≥10% caloric share).
      assert html =~ "Goals:"
      assert html =~ "≥10%"
      refute html =~ "g protein"

      # Preferred foods live in their own section of the "measures up" panel,
      # not in the per-day Goals chips.
      assert html =~ "Preferred foods:"
      assert html =~ "Olive oil"

      # Dismissing stops following and returns to the plain calendar.
      html =
        index_live
        |> element("button", "Stop following")
        |> render_click()

      refute html =~ "How your week measures up"
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
