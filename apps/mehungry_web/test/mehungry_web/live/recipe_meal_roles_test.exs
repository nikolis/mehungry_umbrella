defmodule MehungryWeb.RecipeMealRolesTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]
  import Mehungry.AccountsFixtures

  alias Mehungry.Food.{MealRoleAssignments, RecipeMealRoleRuns}
  alias Mehungry.ObanWorkers.RecipeMealRoleClassificationWorker

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    recipe = recipe_fixture(admin, %{title: "Patlıcan Salatası"})

    MealRoleAssignments.apply_ai_roles(recipe.id, [
      %{role: "main", confidence: 0.55},
      %{role: "meze", confidence: 0.9}
    ])

    %{conn: log_in_user(conn, admin), admin: admin, recipe: recipe}
  end

  defp chip(view, recipe, role),
    do: element(view, ~s(#recipe-#{recipe.id} button[phx-value-role="#{role}"]))

  test "lists a needs-review recipe with its AI roles and confidences", %{conn: conn, recipe: r} do
    {:ok, _view, html} = live(conn, ~p"/professional/recipe-meal-roles")

    assert html =~ "Recipe meal roles"
    assert html =~ "Patlıcan Salatası"
    assert html =~ "Main 0.55"
    assert html =~ "Meze 0.90"
    assert html =~ "recipe-#{r.id}"
  end

  test "toggling chips then Save stores the multi-role set as reviewed", %{
    conn: conn,
    recipe: r,
    admin: admin
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/recipe-meal-roles")

    chip(view, r, "main") |> render_click()
    chip(view, r, "side") |> render_click()
    assert has_element?(view, "#recipe-#{r.id} button[phx-click=save]")

    view |> element("#recipe-#{r.id} button[phx-click=save]") |> render_click()

    # Reviewed rows leave the "Needs review" tab.
    refute has_element?(view, "#recipe-#{r.id}")

    roles = MealRoleAssignments.list_recipe_roles(r.id)
    assert Enum.map(roles, & &1.role) == ["side", "meze"]
    assert Enum.all?(roles, &(&1.reviewed and &1.reviewed_by_id == admin.id))
  end

  test "Discard drops unsaved chip edits", %{conn: conn, recipe: r} do
    {:ok, view, _html} = live(conn, ~p"/professional/recipe-meal-roles")

    chip(view, r, "soup") |> render_click()
    view |> element("#recipe-#{r.id} button[phx-click=discard]") |> render_click()

    refute has_element?(view, "#recipe-#{r.id} button[phx-click=save]")
    assert MealRoleAssignments.roles_for([r.id]) == %{r.id => ["main", "meze"]}
  end

  test "Confirm accepts the AI set as is", %{conn: conn, recipe: r} do
    {:ok, view, _html} = live(conn, ~p"/professional/recipe-meal-roles")

    view |> element("#recipe-#{r.id} button[phx-click=confirm]") |> render_click()

    assert Enum.all?(MealRoleAssignments.list_recipe_roles(r.id), & &1.reviewed)
    refute has_element?(view, "#recipe-#{r.id}")
  end

  test "status tabs and role filter narrow the list", %{conn: conn, recipe: r, admin: admin} do
    other = recipe_fixture(admin, %{title: "Moussaka"})
    {:ok, view, _html} = live(conn, ~p"/professional/recipe-meal-roles")

    view
    |> element(~s(button[phx-click=set_status][phx-value-status=unclassified]))
    |> render_click()

    assert has_element?(view, "#recipe-#{other.id}")
    refute has_element?(view, "#recipe-#{r.id}")

    view |> element(~s(button[phx-click=set_status][phx-value-status=all])) |> render_click()
    view |> element(~s(button[phx-click=filter_role][phx-value-role=meze])) |> render_click()
    assert has_element?(view, "#recipe-#{r.id}")
    refute has_element?(view, "#recipe-#{other.id}")
  end

  test "Classify unclassified starts a tracked run", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/recipe-meal-roles")

    view
    |> element(~s(button[phx-click=classify][phx-value-mode=unclassified]))
    |> render_click()

    run = RecipeMealRoleRuns.latest_run()
    assert run.mode == "unclassified"
    assert_enqueued(worker: RecipeMealRoleClassificationWorker, args: %{"run_id" => run.id})
    assert render(view) =~ "Queued…"
  end

  test "Reclassify resets the recipe and refreshes it when the job reports back", %{
    conn: conn,
    recipe: r
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/recipe-meal-roles")
    view |> element(~s(button[phx-click=set_status][phx-value-status=all])) |> render_click()

    view |> element("#recipe-#{r.id} button[phx-click=reclassify]") |> render_click()
    assert render(view) =~ "Reclassifying…"
    assert MealRoleAssignments.roles_for([r.id]) == %{}

    MealRoleAssignments.apply_ai_roles(r.id, [%{role: "meze", confidence: 0.95}])
    RecipeMealRoleRuns.broadcast_recipe_updated(r.id)

    html = render(view)
    refute html =~ "Reclassifying…"
    assert html =~ "Meze ✓"
  end

  test "non-admins are redirected", %{conn: _conn} do
    conn = log_in_user(build_conn(), user_fixture())
    assert {:error, {_kind, _}} = live(conn, ~p"/professional/recipe-meal-roles")
  end
end
