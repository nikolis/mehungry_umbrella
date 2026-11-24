defmodule MehungryWeb.RecipeTimesLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  require Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    # The fixture gives recipes a time; clear it so one is missing (imports can
    # save recipes without one).
    recipe = recipe_fixture(admin, %{title: "No time yet"})

    Mehungry.Repo.update_all(
      Ecto.Query.from(r in Mehungry.Food.Recipe, where: r.id == ^recipe.id),
      set: [cooking_time_lower_limit: nil, preperation_time_lower_limit: nil]
    )

    %{conn: log_in_user(conn, admin)}
  end

  test "shows coverage and starts an estimation run", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/professional/recipe-times")
    assert html =~ "Recipe times"
    assert has_element?(view, "#missing-count")

    view |> element("#estimate-times") |> render_click()
    assert has_element?(view, "#time-run")
  end

  test "non-admins are redirected" do
    conn = log_in_user(build_conn(), user_fixture())
    assert {:error, {_kind, _}} = live(conn, ~p"/professional/recipe-times")
  end
end
