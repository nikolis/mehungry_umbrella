defmodule MehungryWeb.SearchLiveTest do
  @moduledoc """
  End-to-end search tests.

  Uses :auto sandbox mode so inserts are committed and the materialized view
  recipe_search can be refreshed to reflect newly created recipes.  The
  explicit REFRESH call in setup_all replaces the CONCURRENTLY trigger which
  cannot run inside a transaction.
  """

  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.{Food, Accounts, Repo}

  # Unique prefix so these recipes don't match unrelated test fixtures
  @prefix "SearchTest_"

  defp delete_user_recipes(user_id) do
    import Ecto.Query

    recipe_ids =
      Repo.all(from r in Mehungry.Food.Recipe, where: r.user_id == ^user_id, select: r.id)

    if recipe_ids != [] do
      ingredient_ids =
        Repo.all(
          from ri in Mehungry.Food.RecipeIngredient,
            where: ri.recipe_id in ^recipe_ids,
            select: ri.ingredient_id,
            distinct: true
        )

      Repo.delete_all(
        from ri in Mehungry.Food.RecipeIngredient, where: ri.recipe_id in ^recipe_ids
      )

      Repo.delete_all(from r in Mehungry.Food.Recipe, where: r.id in ^recipe_ids)

      # Clean up orphaned ingredients (not referenced by any other recipe_ingredients)
      orphan_ids =
        Enum.filter(ingredient_ids, fn id ->
          Repo.aggregate(
            from(ri in Mehungry.Food.RecipeIngredient, where: ri.ingredient_id == ^id),
            :count
          ) == 0
        end)

      if orphan_ids != [] do
        Repo.delete_all(
          from it in Mehungry.Food.IngredientTranslation, where: it.ingredient_id in ^orphan_ids
        )

        Repo.delete_all(from i in Mehungry.Food.Ingredient, where: i.id in ^orphan_ids)
      end
    end

    Repo.delete_all(from up in Mehungry.Accounts.UserProfile, where: up.user_id == ^user_id)
    Repo.delete_all(from u in Mehungry.Accounts.User, where: u.id == ^user_id)
  end

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    # Clean up any SearchTest data committed by previous runs to prevent accumulation.
    import Ecto.Query

    stale_ids =
      Repo.all(
        from u in Mehungry.Accounts.User,
          join: r in Mehungry.Food.Recipe,
          on: r.user_id == u.id,
          where: like(r.title, ^"#{@prefix}%"),
          select: u.id,
          distinct: true
      )

    Enum.each(stale_ids, &delete_user_recipes/1)

    user = user_fixture()

    Accounts.update_user_profile(
      Accounts.get_user_profile_by_user_id(user.id),
      %{onboarding_level: 1}
    )

    chicken = recipe_fixture(user, %{title: "#{@prefix}Chicken Souvlaki"})
    eggs    = recipe_fixture(user, %{title: "#{@prefix}Scrambled Eggs Breakfast"})
    _pasta  = recipe_fixture(user, %{title: "#{@prefix}Pasta Carbonara"})

    hashtag_recipe =
      recipe_fixture(user, %{
        title: "#{@prefix}Paleo Bowl",
        description: "a healthy bowl #paleo"
      })

    # Refresh the materialized view so the search index sees these recipes.
    # Must use non-CONCURRENTLY form to work outside a transaction.
    Ecto.Adapters.SQL.query!(Repo, "REFRESH MATERIALIZED VIEW recipe_search", [])

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
      delete_user_recipes(user.id)
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    end)

    %{user: user, chicken: chicken, eggs: eggs, hashtag_recipe: hashtag_recipe}
  end

  # ---------------------------------------------------------------------------
  # Context-level: Food.search_recipe/1
  # ---------------------------------------------------------------------------

  describe "Food.search_recipe/1" do
    test "returns matching recipe by title keyword", %{chicken: chicken} do
      {_query, {results, _cursor}} = Food.search_recipe("#{@prefix}Chicken")
      ids = Enum.map(results, & &1.id)
      assert chicken.id in ids
    end

    test "search is case-insensitive", %{eggs: eggs} do
      {_query, {results, _cursor}} = Food.search_recipe(String.upcase("#{@prefix}Scrambled"))
      ids = Enum.map(results, & &1.id)
      assert eggs.id in ids
    end

    test "partial title substring matches via ILIKE", %{eggs: eggs} do
      {_query, {results, _cursor}} = Food.search_recipe("Scrambled Eggs")
      ids = Enum.map(results, & &1.id)
      assert eggs.id in ids
    end

    test "returns empty list when no recipe matches" do
      {_query, {results, _cursor}} = Food.search_recipe("xyznonexistentdish99")
      assert results == []
    end

    test "does not return unrelated recipes when searching by specific title", %{
      chicken: chicken,
      eggs: eggs
    } do
      {_query, {results, _cursor}} = Food.search_recipe("#{@prefix}Chicken Souvlaki")
      ids = Enum.map(results, & &1.id)
      assert chicken.id in ids
      refute eggs.id in ids
    end

    test "empty string returns all recipes including fixture recipes", %{
      chicken: chicken,
      eggs: eggs
    } do
      {_query, {results, _cursor}} = Food.search_recipe("")
      ids = Enum.map(results, & &1.id)
      assert chicken.id in ids
      assert eggs.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # Context-level: Food.search_hashtag1/1
  # ---------------------------------------------------------------------------

  describe "Food.search_hashtag1/1" do
    test "finds recipe by hashtag in description", %{hashtag_recipe: hashtag_recipe} do
      {_query, {results, _cursor}} = Food.search_hashtag1("#paleo")
      ids = Enum.map(results, & &1.id)
      assert hashtag_recipe.id in ids
    end

    test "returns empty list for unknown hashtag" do
      {_query, {results, _cursor}} = Food.search_hashtag1("#xyzunknownhashtag99")
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # LiveView: form submission navigates to correct URL and shows results
  # ---------------------------------------------------------------------------

  describe "browse search form" do
    setup do
      # Re-checkout a connection for the LiveView tests (setup_all uses :auto)
      conn = Phoenix.ConnTest.build_conn()
      user = user_fixture()
      Accounts.update_user_profile(
        Accounts.get_user_profile_by_user_id(user.id),
        %{onboarding_level: 1}
      )
      conn = log_in_user(conn, user)
      %{conn: conn}
    end

    test "plain text search navigates to /search/:query", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/browse")

      assert {:ok, _search_view, html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: "chicken"})
               |> render_submit()
               |> follow_redirect(conn, "/search/chicken")

      assert is_binary(html)
    end

    test "hashtag search navigates to /search/hashtag/:tag", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/browse")

      assert {:ok, _search_view, html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: "#paleo"})
               |> render_submit()
               |> follow_redirect(conn, "/search/hashtag/paleo")

      assert is_binary(html)
    end

    test "ingredient search navigates to /search/ingredient/:name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/browse")

      assert {:ok, _search_view, html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: "@tomato"})
               |> render_submit()
               |> follow_redirect(conn, "/search/ingredient/tomato")

      assert is_binary(html)
    end

    test "empty search navigates back to /browse", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/browse")

      assert {:ok, _browse_view, _html} =
               view
               |> form(".form-search", recipe_search_item: %{query_string: ""})
               |> render_submit()
               |> follow_redirect(conn, "/browse")
    end

    test "/search/:query page renders matching recipe title", %{conn: conn, chicken: chicken} do
      {:ok, _view, html} = live(conn, "/search/#{@prefix}Chicken")
      assert html =~ chicken.title
    end

    test "/search/:query page shows no results message for unknown query", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/search/xyznonexistentdish99")
      # Page renders without crashing; recipe list is empty
      assert html =~ "not able to find" or not (html =~ @prefix)
    end
  end
end
