defmodule MehungryWeb.NutritionistLive.InvitationsTest do
  @moduledoc """
  Smoke tests for the nutritionist invite page (`/nutritionist/invitations`):
  the search-by-name invite (the path that reaches OAuth users with no usable
  email) and the email fallback.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Accounts, Professionals, Repo, Subscriptions}

  import Swoosh.TestAssertions

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    %{conn: log_in_user(conn, nutritionist), nutritionist: nutritionist}
  end

  defp named_user(name, attrs \\ %{}) do
    user = Mehungry.AccountsFixtures.user_fixture(attrs)
    Repo.update!(Ecto.Changeset.change(user, Map.put(attrs, :name, name)))
  end

  test "searching surfaces matching users and invites one by id", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    # A Facebook login whose only email is a synthetic placeholder — unreachable
    # by email, but must be findable and invitable by name.
    fb_user = named_user("Giorgos Papadakis", %{email: "9988@facebook.user"})

    {:ok, view, _html} = live(conn, "/nutritionist/invitations")

    html = render_change(form(view, "form[phx-change=search_users]"), %{"query" => "giorgos"})
    assert html =~ "Giorgos Papadakis"

    view
    |> element("button[phx-click=invite_user][phx-value-id='#{fb_user.id}']")
    |> render_click()

    assert render(view) =~ "Invitation sent"

    assert [inv] = Professionals.list_sent_invitations(nutritionist.id)
    assert inv.client_id == fb_user.id
    assert inv.status == "pending"
  end

  test "email fallback still works", %{conn: conn, nutritionist: nutritionist} do
    client = Mehungry.AccountsFixtures.user_fixture()

    {:ok, view, _html} = live(conn, "/nutritionist/invitations")

    view
    |> form("form[phx-submit=invite_client]", %{"email" => client.email, "message" => ""})
    |> render_submit()

    assert [inv] = Professionals.list_sent_invitations(nutritionist.id)
    assert inv.client_id == client.id
  end

  test "an unknown address offers to send an onboarding invite", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/nutritionist/invitations")

    html =
      view
      |> form("form[phx-submit=invite_client]", %{"email" => "nobody@example.com", "message" => ""})
      |> render_submit()

    assert html =~ "No m3hungry account found for"
    assert html =~ "nobody@example.com"
    assert html =~ "Send invitation email"
  end

  test "confirming the onboarding invite creates a managed client and emails them", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/invitations")

    view
    |> form("form[phx-submit=invite_client]", %{
      "email" => "newbie@example.com",
      "message" => "Come join me"
    })
    |> render_submit()

    html =
      view
      |> element("[phx-click=confirm_onboard]")
      |> render_click()

    assert html =~ "Invitation email sent to newbie@example.com"

    # A managed, unclaimed client is now assigned to the nutritionist.
    assert [assignment] = Professionals.list_clients(nutritionist.id)
    client = Accounts.get_user!(assignment.client_id)
    assert Accounts.managed_unclaimed?(client)

    assert_email_sent(fn email ->
      assert {_, "newbie@example.com"} = hd(email.to)
      assert email.html_body =~ "/claim/"
    end)
  end

  test "cancelling the onboarding invite hides the prompt and creates nothing", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/invitations")

    view
    |> form("form[phx-submit=invite_client]", %{"email" => "nobody@example.com", "message" => ""})
    |> render_submit()

    html =
      view
      |> element("[phx-click=cancel_onboard]")
      |> render_click()

    refute html =~ "No m3hungry account found for"
    assert [] = Professionals.list_clients(nutritionist.id)
  end
end
