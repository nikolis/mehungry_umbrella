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
