defmodule MehungryWeb.ProfessionalLive.RecipesTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Repo
  alias Mehungry.Food.{IngredientPortion, RecipeIngredient}

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

  test "non-admin is redirected away" do
    conn = log_in_user(build_conn(), user_fixture(%{email: "notadmin@example.com"}))

    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/recipes")
  end
end
