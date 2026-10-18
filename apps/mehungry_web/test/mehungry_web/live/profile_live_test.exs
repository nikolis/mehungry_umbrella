defmodule MehungryWeb.ProfileLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest
  alias Mehungry.{Accounts}
  alias Mehungry.PublishedPlans.PublishedMealPlan
  alias Mehungry.Repo

  setup [:register_and_log_in_user]

  defp onboard(user) do
    user.id
    |> Accounts.get_user_profile_by_user_id()
    |> Accounts.update_user_profile(%{onboarding_level: 1})
  end

  defp published_plan_fixture(user, attrs \\ %{}) do
    {:ok, plan} =
      %PublishedMealPlan{}
      |> PublishedMealPlan.changeset(
        Map.merge(
          %{
            user_id: user.id,
            slug: "plan-#{System.unique_integer([:positive])}",
            title: "My Healthy Week",
            week_start: ~D[2026-10-05],
            days: [],
            macros: %{"energy_kcal" => 1800, "protein_g" => 90},
            recipe_count: 7,
            visibility: "public",
            published_at: DateTime.utc_now() |> DateTime.truncate(:second)
          },
          attrs
        )
      )
      |> Repo.insert()

    plan
  end

  test "Clicking edit button on own recipe navigates to create_recipe edit page", %{
    conn: conn,
    user: user
  } do
    recipe = recipe_fixture(user)
    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    Accounts.update_user_profile(user_profile, %{onboarding_level: 1})

    {:ok, index_live, _html} = live(conn, Routes.profile_index_path(conn, :index))

    index_live
    |> element("#edit-recipe-#{recipe.id}")
    |> render_click()

    assert_redirect(index_live, "/create_recipe/#{recipe.id}")
  end

  test "Clicking delete on own recipe removes it from the created list", %{
    conn: conn,
    user: user
  } do
    recipe = recipe_fixture(user)
    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    Accounts.update_user_profile(user_profile, %{onboarding_level: 1})

    {:ok, index_live, html} = live(conn, Routes.profile_index_path(conn, :index))
    assert html =~ "delete-recipe-#{recipe.id}"

    html =
      index_live
      |> element("#delete-recipe-#{recipe.id}")
      |> render_click()

    refute html =~ "delete-recipe-#{recipe.id}"
    refute Mehungry.Food.get_recipe_no_caching!(recipe.id)
  end

  test "Deleting another user's recipe via a forged id is refused", %{conn: conn, user: user} do
    other = Mehungry.AccountsFixtures.user_fixture()
    victim = recipe_fixture(other)

    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    Accounts.update_user_profile(user_profile, %{onboarding_level: 1})

    {:ok, index_live, _html} = live(conn, Routes.profile_index_path(conn, :index))

    # The button isn't rendered for a recipe the user doesn't own, so push the
    # event directly to prove the server-side owner check holds.
    render_hook(index_live, "delete_recipe", %{"id" => victim.id})

    assert Mehungry.Food.get_recipe_no_caching!(victim.id)
  end

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

    link_to_recipe = "#recipe-card-details-link-recipe#{recipe.id}-#{recipe.id}"

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
    assert html =~ "button_save_recipe"

    link_to_recipe = "#recipe-card-details-link-recipe#{recipe_user2.id}-#{recipe_user2.id}"

    view =
      index_live
      |> element(link_to_recipe)
      |> render_click()

    assert view =~ recipe_user2.title
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
    assert html =~ "button_save_recipe"

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
    assert html =~ "button_save_recipe"

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

  test "own profile shows the Meal Plans tab and hero utility links", %{conn: conn, user: user} do
    onboard(user)

    {:ok, _index_live, html} = live(conn, Routes.profile_index_path(conn, :index))

    assert html =~ "Meal Plans"
    assert html =~ "Edit profile"
    assert html =~ "Connections"
    assert html =~ "My ingredients"
    # The de-noised tabs are gone from the main tab bar.
    refute html =~ "Blueprints"
  end

  test "ingredients tab shows both my and friends' ingredients", %{conn: conn, user: user} do
    onboard(user)

    {:ok, _index_live, html} =
      live(conn, Routes.profile_index_path(conn, :index) <> "?tab=ingredients")

    assert html =~ "My Ingredients"
    assert html =~ "Friends&#39; Ingredients"
    assert html =~ "+ Create ingredient"
  end

  test "Meal Plans tab lists the user's published plans", %{conn: conn, user: user} do
    onboard(user)
    plan = published_plan_fixture(user, %{title: "Mediterranean Week"})

    {:ok, index_live, _html} =
      live(conn, Routes.profile_index_path(conn, :index) <> "?tab=meal_plans")

    html = render(index_live)
    assert html =~ "Mediterranean Week"
    assert html =~ "/meal-plans/#{plan.slug}"
    assert html =~ "Public"
  end

  test "delete-meal-plan unpublishes the owner's plan", %{conn: conn, user: user} do
    onboard(user)
    plan = published_plan_fixture(user)

    {:ok, index_live, _html} =
      live(conn, Routes.profile_index_path(conn, :index) <> "?tab=meal_plans")

    index_live
    |> element("button[phx-value-id='#{plan.id}'][phx-click='delete-meal-plan']")
    |> render_click()

    assert Repo.get(PublishedMealPlan, plan.id) == nil
    refute render(index_live) =~ "/meal-plans/#{plan.slug}"
  end
end
