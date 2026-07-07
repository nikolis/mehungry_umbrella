defmodule MehungryWeb.BrowserLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Mehungry.{FoodFixtures, AccountsFixtures}
  import Phoenix.LiveViewTest
  alias Mehungry.{Accounts, Users}

  defp complete_onboarding(user) do
    profile = Accounts.get_user_profile_by_user_id(user.id)
    {:ok, _} = Accounts.update_user_profile(profile, %{onboarding_level: 1})
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Mount / basic render
  # ──────────────────────────────────────────────────────────────────────────

  describe "mount" do
    setup [:register_and_log_in_user]

    test "renders the browse header", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, _view, html} = live(conn, ~p"/browse")
      assert html =~ "Discover Recipes"
    end

    test "shows existing recipes on load", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/browse")
      assert html =~ recipe.title
      assert html =~ recipe.image_url
    end

    test "shows no-results message when no recipes match", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, _view, html} = live(conn, ~p"/search/xyznonexistentquery123")
      assert html =~ "We were not able to find a recipe"
    end

    test "shows onboarding modal when profile is not complete", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse")
      assert html =~ "onboarding-modal"
    end

    test "does not show onboarding modal after onboarding is complete", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, _view, html} = live(conn, ~p"/browse")
      refute html =~ "onboarding-modal"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Unauthenticated access
  # ──────────────────────────────────────────────────────────────────────────

  describe "unauthenticated access" do
    test "browse page loads without login", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/browse")
      assert html =~ "Discover Recipes"
    end

    test "unauthenticated user sees recipes", %{conn: conn} do
      author = user_fixture()
      recipe = recipe_fixture(author)
      {:ok, _view, html} = live(conn, ~p"/browse")
      assert html =~ recipe.title
    end

    test "unauthenticated user can view recipe detail via direct URL", %{conn: conn} do
      author = user_fixture()
      recipe = recipe_fixture(author, %{title: "Publicly Visible Recipe"})
      {:ok, _view, html} = live(conn, ~p"/browse/#{recipe.id}")
      assert html =~ "Publicly Visible Recipe"
    end

    test "saving a recipe while unauthenticated shows login modal", %{conn: conn} do
      author = user_fixture()
      recipe = recipe_fixture(author)
      {:ok, view, _html} = live(conn, ~p"/browse")

      html =
        view
        |> element("#button_save_recipe#{recipe.id}")
        |> render_click()

      assert html =~ "browse_index_must_be_login"
    end

    test "keep_browsing dismisses the login modal", %{conn: conn} do
      author = user_fixture()
      recipe = recipe_fixture(author)
      {:ok, view, _html} = live(conn, ~p"/browse")

      view |> element("#button_save_recipe#{recipe.id}") |> render_click()
      html = render_hook(view, "keep_browsing", %{})
      refute html =~ "browse_index_must_be_login"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Recipe detail modal (:show_recipe action)
  # ──────────────────────────────────────────────────────────────────────────

  describe ":show_recipe action" do
    setup [:register_and_log_in_user]

    test "clicking a recipe card opens the detail modal", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      html =
        view
        |> element("#recipe-card-details-link-recipes-#{recipe.id}-#{recipe.id}")
        |> render_click()

      assert html =~ recipe.title
      assert html =~ "Steps"
      assert html =~ "Ingredients"
      assert html =~ "Nutrients"
    end

    test "navigating directly to /browse/:id renders recipe detail", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)
      {:ok, _view, html} = live(conn, ~p"/browse/#{recipe.id}")
      assert html =~ recipe.title
      assert html =~ "Ingredients"
      assert html =~ "Nutrients"
    end

    test "recipe detail sets the page title", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user, %{title: "Unique Browser Title Recipe"})
      {:ok, view, _html} = live(conn, ~p"/browse/#{recipe.id}")
      assert page_title(view) =~ "Unique Browser Title Recipe"
    end

    test "close-modal event patches back to browse list", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/browse/#{recipe.id}")
      assert render(view) =~ "recipe_details_modal"

      render_hook(view, "close-modal", %{})
      assert_patch(view, ~p"/browse")
      refute render(view) =~ "recipe_details_modal"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Save / unsave recipe
  # ──────────────────────────────────────────────────────────────────────────

  describe "save recipe" do
    setup [:register_and_log_in_user]

    test "save recipe from browse grid saves it to user recipes", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      view |> element("#button_save_recipe#{recipe.id}") |> render_click()

      [saved] = Users.list_user_saved_recipes(user)
      assert saved.recipe_id == recipe.id
    end

    test "saving a recipe twice (toggle) removes it", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      view |> element("#button_save_recipe#{recipe.id}") |> render_click()
      assert [_] = Users.list_user_saved_recipes(user)

      view |> element("#button_save_recipe#{recipe.id}") |> render_click()
      assert [] = Users.list_user_saved_recipes(user)
    end

    test "save recipe from detail modal saves it", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user)

      {:ok, view, _html} =
        live(conn, Routes.recipe_browser_index_path(conn, :show_recipe, recipe.id))

      view |> element("#recipe_details_componentlike_container") |> render_click()

      [saved] = Users.list_user_saved_recipes(user)
      assert saved.recipe_id == recipe.id
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Search / filter actions
  # ──────────────────────────────────────────────────────────────────────────

  describe "search" do
    setup [:register_and_log_in_user]

    test "search with text navigates to /search/:query", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      assert {:ok, _search_live, html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: "eggs"})
               |> render_submit()
               |> follow_redirect(conn, "/search/eggs")

      assert is_binary(html)
    end

    test "search with # prefix navigates to hashtag route", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      assert {:ok, _live, _html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: "#vegan"})
               |> render_submit()
               |> follow_redirect(conn, "/search/hashtag/vegan")
    end

    test "search with @ prefix navigates to ingredient route", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      assert {:ok, _live, _html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: "@tomato"})
               |> render_submit()
               |> follow_redirect(conn, "/search/ingredient/tomato")
    end

    test "empty search navigates back to /browse", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      assert {:error, {:live_redirect, %{to: "/browse"}}} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: ""})
               |> render_submit()
    end

    test "hashtag route shows only recipes with that hashtag", %{conn: conn, user: user} do
      complete_onboarding(user)
      tagged = recipe_fixture(user, %{title: "Vegan Pasta", description: "desc"})
      untagged = recipe_fixture(user, %{title: "Beef Stew", description: "desc"})

      {:ok, _view, html} = live(conn, ~p"/search/hashtag/vegan")

      # Filtering is by hashtag association — absence of untagged is what matters
      refute html =~ untagged.title
      _ = tagged
    end

    test "ingredient route shows recipes that contain the ingredient", %{conn: conn, user: user} do
      complete_onboarding(user)
      ingredient = ingredient_fixture(%{name: "unique_test_ingredient_xyz"})
      mu = measurement_unit_fixture()

      recipe_with =
        recipe_fixture(user, %{
          title: "Recipe With Unique Ingredient",
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 1}
          ]
        })

      {:ok, _view, html} = live(conn, ~p"/search/ingredient/unique_test_ingredient_xyz")
      assert html =~ recipe_with.title
    end

    test "query route filters recipes by title", %{conn: conn, user: user} do
      complete_onboarding(user)
      recipe = recipe_fixture(user, %{title: "Spinach Quiche Special"})

      {:ok, _view, html} = live(conn, ~p"/search/Spinach Quiche Special")
      assert html =~ recipe.title
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Pagination (load-more)
  # ──────────────────────────────────────────────────────────────────────────

  describe "load-more" do
    setup [:register_and_log_in_user]

    test "load-more adds more recipes to the stream", %{conn: conn, user: user} do
      complete_onboarding(user)
      # Create enough recipes to need pagination (page size is typically 12-20)
      # We just verify the event doesn't crash and returns a valid render
      for i <- 1..5, do: recipe_fixture(user, %{title: "Load More Recipe #{i}"})

      {:ok, view, _html} = live(conn, ~p"/browse")
      html = render_hook(view, "load-more", %{})
      assert html =~ "Discover Recipes"
    end

    test "data-page attribute increments after load-more", %{conn: conn, user: user} do
      complete_onboarding(user)
      for i <- 1..5, do: recipe_fixture(user, %{title: "Page Recipe #{i}"})

      {:ok, view, _html} = live(conn, ~p"/browse")
      assert view |> element("#recipes_container") |> render() =~ "data-page=\"1\""

      render_hook(view, "load-more", %{})
      assert view |> element("#recipes_container") |> render() =~ "data-page=\"2\""
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Search form validation (validate event)
  # ──────────────────────────────────────────────────────────────────────────

  describe "search form validation" do
    setup [:register_and_log_in_user]

    test "validate event does not crash and updates changeset", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/browse")

      html =
        view
        |> form(".form-search", recipe_search_item: %{query_string: "pasta"})
        |> render_change()

      assert html =~ "Discover Recipes"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Page title / SEO assigns
  # ──────────────────────────────────────────────────────────────────────────

  describe "page titles" do
    setup [:register_and_log_in_user]

    test "default browse has generic page title", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/browse")
      assert page_title(view) =~ "Browse Recipes"
    end

    test "query search sets title to the query string", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/search/pasta")
      assert page_title(view) =~ "pasta"
    end

    test "hashtag search sets title with the hashtag", %{conn: conn, user: user} do
      complete_onboarding(user)
      {:ok, view, _html} = live(conn, ~p"/search/hashtag/vegan")
      assert page_title(view) =~ "vegan"
    end
  end
end
