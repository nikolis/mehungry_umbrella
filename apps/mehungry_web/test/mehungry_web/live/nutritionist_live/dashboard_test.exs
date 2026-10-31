defmodule MehungryWeb.NutritionistLive.DashboardTest do
  @moduledoc """
  Smoke tests for the nutritionist dashboard (`/nutritionist`): the activation
  checklist renders for a fresh pro, and completed steps tick off.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Subscriptions}

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.grant_nutritionist(nutritionist.id)
    %{conn: log_in_user(conn, nutritionist), nutritionist: nutritionist}
  end

  test "a fresh pro sees the activation checklist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist")

    assert html =~ "Set up your practice"
    assert html =~ "Create your professional profile"
    assert html =~ "Add or invite your first client"
    # The incomplete, unbuilt payouts step must not appear.
    refute html =~ "Connect payouts"
  end

  test "creating a public profile ticks the first two steps", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, _profile} =
      Professionals.create_professional_profile(%{
        user_id: nutritionist.id,
        display_name: "Dr. Test",
        specialization: "Clinical",
        city: "Athens",
        bio: "Experienced clinical dietitian helping clients eat well.",
        is_public: true
      })

    {:ok, _view, html} = live(conn, "/nutritionist")
    # A completed step is struck through rather than offering its CTA link.
    assert html =~ "line-through"
  end
end
