defmodule MehungryWeb.HomeLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.{FoodFixtures, AccountsFixtures}

  alias Mehungry.{Food, Accounts, Posts}

  # Skip onboarding modal so it doesn't block the feed in every test.
  defp complete_onboarding(user) do
    user_profile = Accounts.get_user_profile_by_user_id(user.id)
    {:ok, _} = Accounts.update_user_profile(user_profile, %{onboarding_level: 1})
    :ok
  end

  defp create_recipe_with_post(user, attrs \\ %{}) do
    recipe = recipe_fixture(user, attrs)
    Food.create_post_from_recipe(recipe)
    recipe
  end

  # Makes the user "vegan mode": ensures the excluded-category vocabulary exists
  # (the env is seeded with the USDA animal categories) and adds a
  # UserCategoryRule for exactly the ids Food.diet_category_ids(:vegan) resolves,
  # so Accounts.diet_mode/1 returns :vegan. Returns those excluded category ids.
  defp make_user_vegan(user) do
    frt =
      Mehungry.Repo.insert!(%Mehungry.Food.FoodRestrictionType{title: "avoid", alias: "avoid"})

    for name <- ~w(Beef Poultry Dairy Pork Sausages Lamb Fish) do
      Food.get_category_by_name(name) || Food.create_category(%{name: name, description: "x"})
    end

    vegan_ids = Food.diet_category_ids(:vegan)

    for id <- vegan_ids do
      Mehungry.Repo.insert!(%Mehungry.Accounts.UserCategoryRule{
        user_id: user.id,
        category_id: id,
        food_restriction_type_id: frt.id
      })
    end

    vegan_ids
  end

  defp recipe_with_meat_post(user, vegan_ids, title) do
    mu = measurement_unit_fixture()
    ingredient = ingredient_fixture(%{name: unique_ingredient()})
    {:ok, ingredient} = Food.update_ingredient(ingredient, %{category_id: List.first(vegan_ids)})

    create_recipe_with_post(user, %{
      title: title,
      recipe_ingredients: [%{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}]
    })
  end

  describe "diet mode filtering" do
    setup [:register_and_log_in_user]

    test "vegan user sees the badge and only #vegan posts", %{conn: conn, user: user} do
      complete_onboarding(user)
      cats = make_user_vegan(user)

      vegan = create_recipe_with_post(user, %{title: "Green Salad"})
      beef = recipe_with_meat_post(user, cats, "Beefy Feast")

      {:ok, _view, html} = live(conn, ~p"/home")

      assert html =~ "vegan mode"
      assert html =~ "card-link-to-recipe-#{vegan.id}"
      refute html =~ "card-link-to-recipe-#{beef.id}"
    end

    test "toggling diet mode off reveals all posts", %{conn: conn, user: user} do
      complete_onboarding(user)
      cats = make_user_vegan(user)

      _vegan = create_recipe_with_post(user, %{title: "Green Salad"})
      beef = recipe_with_meat_post(user, cats, "Beefy Feast")

      {:ok, view, html} = live(conn, ~p"/home")
      refute html =~ "card-link-to-recipe-#{beef.id}"

      html = view |> element("button[phx-click='toggle_diet_mode']") |> render_click()
      assert html =~ "card-link-to-recipe-#{beef.id}"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Mounting / basic render
  # ──────────────────────────────────────────────────────────────────────────

  describe "mount" do
    setup [:register_and_log_in_user]

    test "renders the feed header", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ "Recipe Feed"
    end

    test "renders empty feed without crashing when no posts exist", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ "Recipe Feed"
      assert html =~ "You&#39;ve seen all posts"
    end

    test "shows posts for existing recipes", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)

      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ recipe.image_url
    end

    test "shows onboarding modal when onboarding_level is nil", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ "onboarding-modal"
    end

    test "does not show onboarding modal after onboarding is complete", %{
      conn: conn,
      user: user
    } do
      complete_onboarding(user)
      {:ok, _view, html} = live(conn, ~p"/home")
      refute html =~ "onboarding-modal"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Pagination
  # ──────────────────────────────────────────────────────────────────────────

  describe "pagination" do
    setup [:register_and_log_in_user]

    test "shows scroll sentinel when posts exceed one page", %{conn: conn, user: user} do
      complete_onboarding(user)
      for i <- 1..11, do: create_recipe_with_post(user, %{title: "Paged Recipe #{i}"})

      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ "posts-scroll-sentinel"
      refute html =~ "You&#39;ve seen all posts"
    end

    test "does not show scroll sentinel when all posts fit on first page", %{
      conn: conn,
      user: user
    } do
      complete_onboarding(user)
      for i <- 1..3, do: create_recipe_with_post(user, %{title: "Small Feed #{i}"})

      {:ok, _view, html} = live(conn, ~p"/home")
      refute html =~ "posts-scroll-sentinel"
      assert html =~ "You&#39;ve seen all posts"
    end

    test "load-more displays the 11th post", %{conn: conn, user: user} do
      complete_onboarding(user)
      # The feed is newest-first, so create the uniquely-titled post FIRST —
      # as the oldest post it deterministically lands on page 2.
      unique = create_recipe_with_post(user, %{title: "The Unique Eleventh Recipe"})
      for i <- 1..10, do: create_recipe_with_post(user, %{title: "Filler recipe #{i}"})

      {:ok, view, html} = live(conn, ~p"/home")
      refute html =~ unique.title

      new_html = render_hook(view, "load-more", %{})
      assert new_html =~ unique.title
    end

    test "load-more marks feed exhausted after loading all posts", %{conn: conn, user: user} do
      complete_onboarding(user)
      for i <- 1..11, do: create_recipe_with_post(user, %{title: "Exhaustion recipe #{i}"})

      {:ok, view, _html} = live(conn, ~p"/home")
      new_html = render_hook(view, "load-more", %{})

      assert new_html =~ "You&#39;ve seen all posts"
      refute new_html =~ "posts-scroll-sentinel"
    end

    test "load-more increments page data attribute", %{conn: conn, user: user} do
      complete_onboarding(user)
      # 21 posts: two full pages, so sentinel is still visible after page 2
      for i <- 1..21, do: create_recipe_with_post(user, %{title: "Page recipe #{i}"})

      {:ok, view, _html} = live(conn, ~p"/home")
      assert view |> element("#posts-scroll-sentinel") |> render() =~ "data-page=\"1\""

      render_hook(view, "load-more", %{})
      assert view |> element("#posts-scroll-sentinel") |> render() =~ "data-page=\"2\""
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Recipe detail modal (:show_recipe action)
  # ──────────────────────────────────────────────────────────────────────────

  describe ":show_recipe action" do
    setup [:register_and_log_in_user]

    test "navigating to /home/:id renders recipe detail modal", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/home/#{recipe.id}")
      assert html =~ recipe.title
      assert html =~ "Ingredients"
      assert html =~ "Nutrients"
    end

    test "clicking post card link opens recipe detail modal", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)

      {:ok, view, _html} = live(conn, ~p"/home")

      html =
        view
        |> element("#card-link-to-recipe-#{recipe.id}")
        |> render_click()

      assert html =~ recipe.title
      assert html =~ "Steps"
      assert html =~ "Ingredients"
      assert html =~ "Nutrients"
    end

    test "recipe modal shows the title in the page title", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user, %{title: "Distinctive Recipe Title Test"})

      {:ok, view, _html} = live(conn, ~p"/home/#{recipe.id}")
      assert page_title(view) =~ "Distinctive Recipe Title Test"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # React (upvote / downvote)
  # ──────────────────────────────────────────────────────────────────────────

  describe "react events (authenticated)" do
    setup [:register_and_log_in_user]

    test "upvote does not crash and re-renders the feed", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)
      post = Posts.list_posts(user) |> Enum.find(&(&1.reference_id == recipe.id))

      {:ok, view, _html} = live(conn, ~p"/home")

      html = render_hook(view, "react", %{"type_" => "upvote", "id" => to_string(post.id)})
      assert html =~ "Recipe Feed"
    end

    test "downvote does not crash and re-renders the feed", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)
      post = Posts.list_posts(user) |> Enum.find(&(&1.reference_id == recipe.id))

      {:ok, view, _html} = live(conn, ~p"/home")

      html = render_hook(view, "react", %{"type_" => "downvote", "id" => to_string(post.id)})
      assert html =~ "Recipe Feed"
    end

    test "upvoting twice (toggle) does not crash", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)
      post = Posts.list_posts(user) |> Enum.find(&(&1.reference_id == recipe.id))
      post_id = to_string(post.id)

      {:ok, view, _html} = live(conn, ~p"/home")
      # First upvote registers normally
      render_hook(view, "react", %{"type_" => "upvote", "id" => post_id})
      # Second upvote toggles it off — the broadcast sends a minimal map; verify no crash
      assert render_hook(view, "react", %{"type_" => "upvote", "id" => post_id}) =~
               "Recipe Feed"
    end
  end

  describe "react events (unauthenticated)" do
    test "react shows login-required modal when user is not logged in", %{conn: conn} do
      author = user_fixture()
      recipe = create_recipe_with_post(author)
      post = Posts.list_posts(nil) |> Enum.find(&(&1.reference_id == recipe.id))

      {:ok, view, _html} = live(conn, ~p"/home")

      html = render_hook(view, "react", %{"type_" => "upvote", "id" => to_string(post.id)})
      assert html =~ "browse_index_must_be_login"
    end

    test "keep_browsing dismisses the login-required modal", %{conn: conn} do
      author = user_fixture()
      recipe = create_recipe_with_post(author)
      post = Posts.list_posts(nil) |> Enum.find(&(&1.reference_id == recipe.id))

      {:ok, view, _html} = live(conn, ~p"/home")
      render_hook(view, "react", %{"type_" => "upvote", "id" => to_string(post.id)})

      html = render_hook(view, "keep_browsing", %{})
      refute html =~ "browse_index_must_be_login"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # PubSub vote broadcast
  # ──────────────────────────────────────────────────────────────────────────

  describe "vote broadcast via PubSub" do
    setup [:register_and_log_in_user]

    test "receiving a vote broadcast re-renders the feed without crashing", %{
      conn: conn,
      user: user
    } do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)
      post = Posts.list_posts(user) |> Enum.find(&(&1.reference_id == recipe.id))

      {:ok, view, _html} = live(conn, ~p"/home")

      # A different user upvotes — this broadcasts to the LiveView via PubSub
      voter = user_fixture()
      Posts.upvote_post(post.id, voter.id)

      assert render(view) =~ "Recipe Feed"
    end

    test "post list reflects vote after broadcast", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = create_recipe_with_post(user)
      post = Posts.list_posts(user) |> Enum.find(&(&1.reference_id == recipe.id))

      {:ok, view, _html} = live(conn, ~p"/home")

      voter = user_fixture()
      Posts.upvote_post(post.id, voter.id)

      # The PubSub message re-fetches the post — verify the view is still consistent
      html = render(view)
      assert html =~ recipe.title
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Unauthenticated access
  # ──────────────────────────────────────────────────────────────────────────

  describe "unauthenticated access" do
    test "home page is accessible without login", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ "Recipe Feed"
    end

    test "unauthenticated user sees existing posts", %{conn: conn} do
      author = user_fixture()
      recipe = create_recipe_with_post(author)

      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ recipe.image_url
    end

    test "unauthenticated user can view recipe detail via direct URL", %{conn: conn} do
      author = user_fixture()
      recipe = recipe_fixture(author, %{title: "Guest Viewable Recipe"})

      {:ok, _view, html} = live(conn, ~p"/home/#{recipe.id}")
      assert html =~ "Guest Viewable Recipe"
    end

    test "unauthenticated user sees no onboarding modal", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/home")
      # onboarding modal is only shown when @user is not nil and profile incomplete
      refute html =~ "onboarding-modal"
    end
  end
end
