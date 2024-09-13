defmodule MehungryWeb.BrowserLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest
  alias Mehungry.{Accounts}

  setup [:register_and_log_in_user]

  test "Test BrowserLive ", %{conn: conn, user: user} do
    recipe = recipe_fixture(user)
      user_profile = Accounts.get_user_profile_by_user_id(user.id)

      Accounts.update_user_profile(
        user_profile,
        %{onboarding_level: 1}
      )

      {:ok, index_live, html} = live(conn, Routes.recipe_browser_index_path(conn, :index))
      assert html =~ recipe.image_url
      assert html =~ recipe.title
    
    link_to_recipe = "#recipe-card-details-link-#{recipe.id}"

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
