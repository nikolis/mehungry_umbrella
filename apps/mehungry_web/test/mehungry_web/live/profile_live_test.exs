defmodule MehungryWeb.ProfileLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest
  alias Mehungry.{Accounts}

  setup [:register_and_log_in_user]

  test "Test Visit Own Profile Page ", %{conn: conn, user: user} do
    recipe = recipe_fixture(user)
    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    Accounts.update_user_profile(
      user_profile,
      %{onboarding_level: 1}
    )

    {:ok, index_live, html} = live(conn, Routes.profile_index_path(conn, :index))
    assert html =~ recipe.image_url
    assert html =~ recipe.title
    assert html =~ "edit-recipe"

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

  test "Test Visit Other Profile Page ", %{conn: conn, user: user} do
    %{conn: conn, user: user2} = register_and_log_in_user(%{conn: conn})
    recipe = recipe_fixture(user)
    recipe_user2 = recipe_fixture(user2)

    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    Accounts.update_user_profile(
      user_profile,
      %{onboarding_level: 1}
    )

    {:ok, index_live, html} = live(conn, Routes.profile_index_path(conn, :show, user2.id))
    assert html =~ recipe_user2.image_url
    assert html =~ recipe_user2.title
    assert html =~ "recipe_like_container"

    link_to_recipe = "#recipe-card-details-link-#{recipe_user2.id}"

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
