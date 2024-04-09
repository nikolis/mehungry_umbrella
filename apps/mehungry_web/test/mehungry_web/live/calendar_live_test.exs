defmodule MehungryWeb.CalendarLiveTest do
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.History

  describe "Caledar Operations Test" do
    setup [:register_and_log_in_user]

    test "Recipe User Meals with current date show in page", %{conn: conn, user: user} do
      recipe1 = recipe_fixture(user)
      recipe2 = recipe_fixture(user)
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

      {:ok, user_meal} = History.create_user_meal(recipe_user_meal_params)

      {:ok, _index_live, html} = live(conn, ~p"/calendar")
      # assert html =~ "The title"
    end
  end
end
