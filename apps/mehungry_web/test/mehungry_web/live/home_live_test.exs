defmodule MehungryWeb.HomeLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.{FoodFixtures}
  alias Mehungry.{Food, Accounts}

  describe "Home Live Test" do
    setup [:register_and_log_in_user]

    test "View the post of the created recipe", %{conn: conn, user: user} do
      recipe = recipe_fixture(user)
      _recipe = Food.get_recipe!(recipe.id)

      user_profile = Accounts.get_user_profile_by_user_id(user.id)

      Accounts.update_user_profile(
        user_profile,
        %{onboarding_level: 1}
      )

      {:ok, _index_live, html} = live(conn, Routes.home_index_path(conn, :index))
      assert html =~ recipe.image_url
    end

    test "View the details of the created recipes", %{conn: conn, user: user} do
      recipe = recipe_fixture(user)
      _recipe = Food.get_recipe!(recipe.id)

      user_profile = Accounts.get_user_profile_by_user_id(user.id)

      Accounts.update_user_profile(
        user_profile,
        %{onboarding_level: 1}
      )

      {:ok, index_live, _html} =
        live(conn, Routes.home_index_path(conn, :index))

      link_to_recipe = "#link-to-recipe-#{recipe.id}"

      view =
        index_live
        |> element(link_to_recipe)
        |> render_click()

      assert view =~ recipe.title
      assert view =~ "steps"
      assert view =~ "ingredients"
      assert view =~ "nutrients"
    end
  end
end
