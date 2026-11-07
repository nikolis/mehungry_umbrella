defmodule MehungryWeb.ProfileLive.ProgressTest do
  @moduledoc "The owner-only period-based progress journal on /profile?tab=progress."

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Accounts
  alias Mehungry.AccountsFixtures
  alias Mehungry.Professionals
  alias Mehungry.Progress

  setup [:register_and_log_in_user]

  setup %{user: user} do
    # Past the onboarding wizard so the profile renders its tabs.
    user.id
    |> Accounts.get_user_profile_by_user_id()
    |> Accounts.update_user_profile(%{onboarding_level: 1})

    :ok
  end

  test "first visit bootstraps a self period with the journal UI", %{conn: conn, user: user} do
    {:ok, _view, html} = live(conn, ~p"/profile?tab=progress")

    assert html =~ "self-tracked"
    assert html =~ "Diary"
    assert html =~ "Goals &amp; tracked metrics"
    assert html =~ "Start over"

    active = Progress.active_period(user.id)
    assert active.kind == "self"
  end

  test "logging an entry updates the diary and (with 2+ points) the chart", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/profile?tab=progress")

    view
    |> form("form[phx-submit=log_entry]", %{
      "entry" => %{"entry_date" => "2026-11-01", "weight_kg" => "80", "note" => "day one"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Entry saved."
    assert html =~ "day one"

    # A second dated point makes weight chartable → chart + "logged by you" legend.
    view
    |> form("form[phx-submit=log_entry]", %{
      "entry" => %{"entry_date" => "2026-11-05", "weight_kg" => "79"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "logged by you"
    assert length(Progress.list_entries(user.id, Progress.active_period(user.id).id)) == 2
  end

  test "reset closes the period and starts a new one", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/profile?tab=progress")
    first = Progress.active_period(user.id)

    view |> element("button[phx-click=reset_period]") |> render_click()

    html = render(view)
    assert html =~ "Fresh start!"
    active = Progress.active_period(user.id)
    assert active.id != first.id
    # The closed period shows in the history list.
    assert html =~ "Progress history"
  end

  test "share toggle without a nutritionist flashes an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/profile?tab=progress")

    view |> element("button[phx-click=toggle_share]") |> render_click()
    assert render(view) =~ "You don&#39;t have a nutritionist to share with yet."
  end

  test "a nutritionist-aligned period pauses self-logging and shows the notice", %{
    conn: conn,
    user: user
  } do
    pro = AccountsFixtures.user_fixture()
    {:ok, inv} = Professionals.invite_client(pro.id, user.email)
    {:ok, _} = Professionals.accept_invitation(inv.id, user.id)

    {:ok, view, html} = live(conn, ~p"/profile?tab=progress")

    assert html =~ "Your nutritionist now tracks your progress"
    assert html =~ "with nutritionist"
    # No self-logging form on an aligned period.
    refute has_element?(view, "form[phx-submit=log_entry]")
    refute has_element?(view, "button[phx-click=reset_period]")
  end
end
