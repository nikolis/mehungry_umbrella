defmodule MehungryWeb.NutritionistLive.UserInvitationsTest do
  @moduledoc """
  The client-facing invitations page (`/notifications/invitations`) shows the
  client's current nutritionist and lets them undo the link themselves.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Professionals

  setup do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()
    %{nutritionist: nutritionist, client: client}
  end

  defp link_client(nutritionist, client) do
    {:ok, inv} = Professionals.invite_client_by_id(nutritionist.id, client.id)
    {:ok, _assignment} = Professionals.accept_invitation(inv.id, client.id)
    :ok
  end

  test "shows the linked nutritionist and removes the link on click",
       %{conn: conn, nutritionist: nutritionist, client: client} do
    :ok = link_client(nutritionist, client)

    {:ok, view, html} = live(log_in_user(conn, client), ~p"/notifications/invitations")

    assert html =~ "Your current nutritionist"
    assert render(view) =~ nutritionist.email

    view |> element("button", "Remove") |> render_click()

    assert render(view) =~ "Nutritionist removed."
    assert is_nil(Professionals.get_assignment_for_client(client.id))
  end

  test "shows no nutritionist banner when the client is unlinked",
       %{conn: conn, client: client} do
    {:ok, _view, html} = live(log_in_user(conn, client), ~p"/notifications/invitations")

    refute html =~ "Your current nutritionist"
  end
end
