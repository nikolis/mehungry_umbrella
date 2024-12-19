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
    assert view =~ "Steps"
    assert view =~ "Ingredients"
    assert view =~ "Nutrients"
  end

  test "Test BrowserLive Like on recipe details ", %{conn: conn, user: user} do
    recipe = recipe_fixture(user)
    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    Accounts.update_user_profile(
      user_profile,
      %{onboarding_level: 1}
    )

    {:ok, index_live, html} =
      live(conn, Routes.recipe_browser_index_path(conn, :show_recipe, recipe.id))

    assert html =~ recipe.image_url
    assert html =~ recipe.title

    assert html =~ recipe.title
    assert html =~ "Steps"
    assert html =~ "Ingredients"
    assert html =~ "Nutrients"
    like_recipe_button = "#recipe_details_componentlike_container"

    view =
      index_live
      |> element(like_recipe_button)
      |> render_click()

    assert view =~ recipe.title
    [user_saved_recipe] = Mehungry.Users.list_user_saved_recipes(user)
    assert user_saved_recipe.recipe_id == recipe.id
  end

  test "Test BrowserLive  Like Recipe", %{conn: conn, user: user} do
    recipe = recipe_fixture(user)
    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    Accounts.update_user_profile(
      user_profile,
      %{onboarding_level: 1}
    )

    {:ok, index_live, html} = live(conn, Routes.recipe_browser_index_path(conn, :index))
    assert html =~ recipe.image_url
    assert html =~ recipe.title

    like_recipe_button = "#button_save_recipe#{recipe.id}"

    view =
      index_live
      |> element(like_recipe_button)
      |> render_click()

    assert view =~ recipe.title
    [user_saved_recipe] = Mehungry.Users.list_user_saved_recipes(user)
    assert user_saved_recipe.recipe_id == recipe.id

    _element =
      index_live
      |> element(like_recipe_button)
  end

  test "Test BrowserLive -> Recipe Details -> Listing", %{conn: conn, user: user} do
    recipe = recipe_fixture(user)

    recipe_2 =
      recipe_fixture(user, %{
        description: "description with #hashtag",
        title: "Title for the uknow"
      })

    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    Accounts.update_user_profile(
      user_profile,
      %{onboarding_level: 1}
    )

    {:ok, index_live, html} =
      live(conn, Routes.recipe_browser_index_path(conn, :index, "#hashtag"))

    assert html =~ recipe_2.title
    assert html =~ recipe.title == false
    assert html =~ "Nutrients" == false

    _result =
      element(index_live, "#recipe-card-details-link-" <> Integer.to_string(recipe_2.id))
      |> render_click()

    assert_patch(index_live)
    html = render(index_live)
    assert html =~ recipe_2.title
    assert html =~ "Nutrients"
    assert html =~ "Nutrients" == true
  end
end
