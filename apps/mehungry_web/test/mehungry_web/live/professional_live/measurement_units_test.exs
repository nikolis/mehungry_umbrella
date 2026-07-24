defmodule MehungryWeb.ProfessionalLive.MeasurementUnitsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    gram = measurement_unit_fixture(%{name: "gram"})
    cup = measurement_unit_fixture(%{name: "cup"})

    %{conn: conn, gram: gram, cup: cup}
  end

  test "lists all measurement units in the stream", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/measurement_units")

    assert html =~ "Measurement Units"
    assert html =~ "gram"
    assert html =~ "cup"
  end

  test "creates a measurement unit and inserts the row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/measurement_units")

    view
    |> element("a", "New Measurement Unit")
    |> render_click()

    assert_patch(view, ~p"/professional/measurement_units/new")

    html =
      view
      |> form("#measurement-unit-form", measurement_unit: %{name: "tablespoon", url: "http://x"})
      |> render_submit()

    assert html =~ "tablespoon"
    assert Food.get_measurement_unit_by_name("tablespoon") != []
  end

  test "edits a measurement unit", %{conn: conn, gram: gram} do
    {:ok, view, _html} = live(conn, ~p"/professional/measurement_units")

    view
    |> element("a.opacity-0[href='/professional/measurement_units/#{gram.id}/edit']")
    |> render_click()

    assert_patch(view, ~p"/professional/measurement_units/#{gram.id}/edit")

    view
    |> form("#measurement-unit-form", measurement_unit: %{alternate_name: "gramme"})
    |> render_submit()

    assert Food.get_measurement_unit!(gram.id).alternate_name == "gramme"
  end

  test "deletes an unreferenced measurement unit", %{conn: conn} do
    pinch = measurement_unit_fixture(%{name: "pinch"})
    {:ok, view, _html} = live(conn, ~p"/professional/measurement_units")

    view
    |> element("a.opacity-0[phx-value-id='#{pinch.id}']")
    |> render_click()

    assert Food.get_measurement_unit!(pinch.id) == nil
  end

  test "delete of a referenced unit flashes an error and keeps the row", %{conn: conn, gram: gram} do
    # gram is referenced by ingredient portions in the seeded/fixture data.
    ingredient = Mehungry.FoodFixtures.ingredient_fixture(%{name: "flour"})

    {:ok, _portion} =
      Food.create_ingredient_portion(%{
        ingredient_id: ingredient.id,
        measurement_unit_id: gram.id,
        gram_weight: 100.0,
        amount: 1.0
      })

    {:ok, view, _html} = live(conn, ~p"/professional/measurement_units")

    html =
      view
      |> element("a.opacity-0[phx-value-id='#{gram.id}']")
      |> render_click()

    assert html =~ "Cannot delete measurement unit"
    assert Food.get_measurement_unit!(gram.id) != nil
  end

  test "non-admin is redirected away", %{} do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/measurement_units")
  end
end
