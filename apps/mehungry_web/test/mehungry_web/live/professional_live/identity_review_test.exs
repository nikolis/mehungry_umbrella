defmodule MehungryWeb.ProfessionalLive.IdentityReviewTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.IdentityResolution

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    spinach = ingredient_fixture(%{name: "spinach"})

    {:ok, identity, :created} =
      Food.add_identity_candidate(%{
        ingredient_id: spinach.id,
        scientific_name: "Spinacia oleracea",
        rank: "species",
        source: "usda_fdc",
        confidence: 0.9
      })

    %{conn: conn, spinach: spinach, identity: identity}
  end

  test "the review route renders the pending candidate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/science/identity-review")

    assert html =~ "Identity verification"
    assert html =~ "spinach"
    assert html =~ "Spinacia oleracea"
    assert html =~ "Verify"
  end

  test "the pipeline page links to the review route", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/science")

    assert html =~ ~p"/professional/science/identity-review"
    assert html =~ "Identity review"
  end

  test "Verify promotes the identity and drops the row", %{
    conn: conn,
    spinach: spinach,
    identity: identity
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science/identity-review")

    assert render(view) =~ "Spinacia oleracea"

    view
    |> element("button[phx-click='verify'][phx-value-id='#{identity.id}']")
    |> render_click()

    refute render(view) =~ "Spinacia oleracea"

    verified = Food.verified_identity(spinach.id)
    assert verified.scientific_name == "Spinacia oleracea"
    assert Food.get_identity!(identity.id).status == "verified"
  end

  test "Reject dismisses the identity and drops the row", %{
    conn: conn,
    spinach: spinach,
    identity: identity
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science/identity-review")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{identity.id}']")
    |> render_click()

    refute render(view) =~ "Spinacia oleracea"
    assert Food.get_identity!(identity.id).status == "rejected"
    assert Food.verified_identity(spinach.id) == nil
  end

  test "the skipped section lists processed ingredients that got no identity, with the reason", %{
    conn: conn
  } do
    no_name = ingredient_fixture(%{name: "mystery blend"})
    errored = ingredient_fixture(%{name: "broken lookup"})
    IdentityResolution.record_attempt(no_name.id, "no_scientific_name")
    IdentityResolution.record_attempt(errored.id, "error", "fdc 404")

    {:ok, _view, html} = live(conn, ~p"/professional/science/identity-review")

    assert html =~ "Skipped (no identity)"
    assert html =~ "mystery blend"
    assert html =~ "No scientific name in USDA data"
    assert html =~ "broken lookup"
    assert html =~ "fdc 404"
  end

  test "non-admin is redirected away from the review route" do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/science/identity-review")
  end
end
