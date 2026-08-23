defmodule MehungryWeb.ProfessionalLive.RecipesTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Repo
  alias Mehungry.Food.{HashtagReconciliation, HashtagReconciliations, IngredientPortion, RecipeIngredient}
  alias Mehungry.ObanWorkers.HashtagReconciliationWorker

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)
    recipe = recipe_fixture(admin)
    %{conn: conn, recipe: recipe}
  end

  # Seeds a legacy row bypassing the changeset so ingredient_portion_id can be nil.
  defp seed_ri(recipe, ingredient, unit) do
    Repo.insert!(%RecipeIngredient{
      recipe_id: recipe.id,
      ingredient_id: ingredient.id,
      measurement_unit_id: unit.id,
      ingredient_portion_id: nil,
      quantity: 2.0
    })
  end

  test "assess (dry run) renders the report and writes nothing", %{conn: conn, recipe: recipe} do
    slice = measurement_unit_fixture(%{name: "slice"})
    ingredient = ingredient_fixture()
    ri = seed_ri(recipe, ingredient, slice)

    {:ok, view, _html} = live(conn, ~p"/professional/recipes")

    view |> element("button", "Assess portions") |> render_click()
    html = render_async(view)

    assert html =~ "Ingredient portion reconciliation"
    assert html =~ "Dry run"
    assert html =~ "Pairs needing admin review"

    # Dry run must not link the row.
    assert Repo.get!(RecipeIngredient, ri.id).ingredient_portion_id == nil
  end

  test "reconcile synthesizes a mass portion and links the row", %{conn: conn, recipe: recipe} do
    oz = measurement_unit_fixture(%{name: "oz"})
    ingredient = ingredient_fixture()
    ri = seed_ri(recipe, ingredient, oz)

    {:ok, view, _html} = live(conn, ~p"/professional/recipes")

    view |> element("button", "Reconcile portions") |> render_click()
    html = render_async(view)

    assert html =~ "Applied"

    linked = Repo.get!(RecipeIngredient, ri.id)
    assert linked.ingredient_portion_id

    portion = Repo.get!(IngredientPortion, linked.ingredient_portion_id)
    assert portion.measurement_unit_id == oz.id
    assert_in_delta portion.gram_weight, 28.3495, 0.001
  end

  test "searching lists a recipe and deleting it removes it with its references", %{
    conn: conn,
    recipe: recipe
  } do
    unit = measurement_unit_fixture(%{name: "cup"})
    ingredient = ingredient_fixture()
    ri = seed_ri(recipe, ingredient, unit)

    {:ok, view, _html} = live(conn, ~p"/professional/recipes")

    html =
      view
      |> form("#admin-recipe-search", %{"query" => recipe.title})
      |> render_change()

    assert html =~ recipe.title

    view
    |> element("button[phx-value-id='#{recipe.id}']", "Delete")
    |> render_click()

    refute Repo.get(Mehungry.Food.Recipe, recipe.id)
    refute Repo.get(RecipeIngredient, ri.id)
  end

  test "Reconcile hashtags fans out one job per recipe and shows progress", %{
    conn: conn,
    recipe: recipe
  } do
    # Simulate production drift: the recipe's description tag lost its join row.
    recipe = Repo.update!(Ecto.Changeset.change(recipe, description: "look a #stray"))
    Repo.delete_all(Mehungry.Food.RecipeHashtag)

    {:ok, view, _html} = live(conn, ~p"/professional/recipes")

    view |> element("button", "Reconcile hashtags") |> render_click()
    render_async(view)

    assert_enqueued(worker: HashtagReconciliationWorker, args: %{recipe_id: recipe.id})

    row = Repo.get_by!(HashtagReconciliation, recipe_id: recipe.id)

    assert :ok =
             perform_job(HashtagReconciliationWorker, %{
               "reconciliation_id" => row.id,
               "recipe_id" => recipe.id
             })

    # The stray tag is reconnected and searchable again.
    assert Mehungry.Hashtag.get_hashtag_by_title("stray")

    # The coalesced flush repaints the progress card once its timer fires.
    Process.send(view.pid, :flush_hashtag_counts, [])
    html = render(view)
    assert html =~ "Hashtag reconciliation"
    assert html =~ "Completed"
  end

  test "Reset clears hashtag reconciliation status", %{conn: conn, recipe: recipe} do
    row = HashtagReconciliations.upsert_pending(recipe.id)
    HashtagReconciliations.mark_completed(row.id, 1)

    {:ok, view, _html} = live(conn, ~p"/professional/recipes")

    view |> element("button", "Reset") |> render_click()

    assert Repo.aggregate(HashtagReconciliation, :count) == 0
  end

  test "non-admin is redirected away" do
    conn = log_in_user(build_conn(), user_fixture(%{email: "notadmin@example.com"}))

    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/recipes")
  end
end
