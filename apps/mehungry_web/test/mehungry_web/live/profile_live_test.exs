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
    assert view =~ "Steps"
    assert view =~ "Ingredients"
    assert view =~ "Nutrients"
  end

  test "Test Own Profile Remove Recipe From Likes ", %{conn: conn, user: user} do
    ## register_and_log_in_user(%{conn: conn})
    user2 = Mehungry.AccountsFixtures.user_fixture()
    recipe = recipe_fixture(user2)
    recipe2 = recipe_fixture(user2)

    Mehungry.Users.save_user_recipe(user.id, recipe.id)
    Mehungry.Users.save_user_recipe(user.id, recipe2.id)
    user_profile = Accounts.get_user_profile_by_user_id(user.id)

    Accounts.update_user_profile(
      user_profile,
      %{onboarding_level: 1}
    )

    {:ok, index_live, _html} = live(conn, Routes.profile_index_path(conn, :index))
    tab_button_profile_saved_recipes = "#tab_button_profile_saved_recipes"

    view =
      index_live
      |> element(tab_button_profile_saved_recipes)
      |> render_click()

    assert view =~ recipe.image_url
    assert view =~ recipe.title

    button_remove_recipe = "#button_save_recipe#{recipe.id}"

    _view =
      index_live
      |> element(button_remove_recipe)
      |> render_click()

    {_user_profile, _, user_recipes} =
      Accounts.get_user_essentials(user)

    assert length(user_recipes) == 1
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
    assert view =~ "Steps"
    assert view =~ "Ingredients"
    assert view =~ "Nutrients"
  end

  test "Test Visit Other Profile Page Like Recipe from Listing ", %{conn: conn, user: user} do
    user2 = Mehungry.AccountsFixtures.user_fixture()
    _recipe = recipe_fixture(user)
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

    _view =
      index_live
      |> element("#button_save_recipe" <> Integer.to_string(recipe_user2.id))
      |> render_click()

    {_user_profile, _user_follows, user_recipes} =
      Accounts.get_user_essentials(user)

    assert user_recipes == [recipe_user2.id]

    {_user_profile, _user_follows, user_recipes} =
      Accounts.get_user_essentials(user2)

    assert user_recipes == []
  end

  test "Test Visit Other Profile Page Like Recipe from Listing and follow user", %{
    conn: conn,
    user: user
  } do
    user2 = Mehungry.AccountsFixtures.user_fixture()
    _recipe = recipe_fixture(user)
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

    _view =
      index_live
      |> element("#toggle_user_follow" <> Integer.to_string(user2.id))
      |> render_click()

    {_user_profile, [user_follow], _user_recipes} =
      Accounts.get_user_essentials(user)

    assert user_follow.follow_id == user2.id

    {_user_profile, _user_follows, user_recipes} =
      Accounts.get_user_essentials(user2)

    assert user_recipes == []
  end
end
