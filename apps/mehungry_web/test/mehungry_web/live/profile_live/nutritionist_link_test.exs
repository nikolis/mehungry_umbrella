defmodule MehungryWeb.ProfileLive.NutritionistLinkTest do
  @moduledoc """
  A client can see their linked nutritionist from their own profile (under the
  Connections panel) and undo the link there.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Professionals

  setup do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()

    {:ok, inv} = Professionals.invite_client_by_id(nutritionist.id, client.id)
    {:ok, _assignment} = Professionals.accept_invitation(inv.id, client.id)

    %{nutritionist: nutritionist, client: client}
  end

  test "Connections panel shows the nutritionist and removes the link",
       %{conn: conn, nutritionist: nutritionist, client: client} do
    {:ok, view, _html} =
      live(log_in_user(conn, client), ~p"/profile?#{[tab: "connected_accounts"]}")

    assert render(view) =~ "Your nutritionist"
    assert render(view) =~ nutritionist.email

    view |> element("button", "Remove") |> render_click()

    assert render(view) =~ "Nutritionist removed."
    refute render(view) =~ "Your nutritionist"
    assert is_nil(Professionals.get_assignment_for_client(client.id))
  end
end
