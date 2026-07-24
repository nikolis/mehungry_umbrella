defmodule MehungryWeb.IngredientReconciliationTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.ObanWorkers.IngredientReconciliationWorker

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin)}
  end

  test "renders the progress bar", %{conn: conn} do
    ingredient_fixture(%{name: "salt table", food_class: "Foundation"})

    {:ok, _view, html} = live(conn, ~p"/professional/ingredients/reconciliation")

    assert html =~ "Ingredient Reconciliation"
    assert html =~ "Backfilled:"
  end

  test "Start Backfill enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/ingredients/reconciliation")

    view
    |> element("button[phx-click='backfill']")
    |> render_click()

    assert_enqueued(worker: IngredientReconciliationWorker)
  end

  test "Refresh re-renders progress", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/ingredients/reconciliation")

    html =
      view
      |> element("button[phx-click='refresh']")
      |> render_click()

    assert html =~ "Backfilled:"
  end

  test "non-admin is redirected away", %{} do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/ingredients/reconciliation")
  end
end
