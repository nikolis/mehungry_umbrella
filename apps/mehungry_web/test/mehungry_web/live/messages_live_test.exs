defmodule MehungryWeb.MessagesLiveTest do
  @moduledoc """
  Smoke tests for the client side of the client↔nutritionist thread (`/messages`):
  empty state without a nutritionist, sending, and read-on-open.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo}
  alias Mehungry.Professionals.TutorClientAssignment

  defp with_nutritionist(client) do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    nutritionist = Repo.update!(Ecto.Changeset.change(nutritionist, name: "Dr. Nutri"))

    Repo.insert!(%TutorClientAssignment{
      professional_id: nutritionist.id,
      client_id: client.id
    })

    nutritionist
  end

  setup %{conn: conn} do
    client = Mehungry.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, client), client: client}
  end

  test "empty state when the client has no nutritionist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/messages")
    assert html =~ "have a nutritionist yet"
  end

  test "client sends a message to their nutritionist", %{conn: conn, client: client} do
    nutritionist = with_nutritionist(client)

    {:ok, view, html} = live(conn, "/messages")
    assert html =~ "Dr. Nutri"

    html =
      view
      |> form("form[phx-submit='send_message']", %{body: "Hi, I have a question"})
      |> render_submit()

    assert html =~ "Hi, I have a question"
    assert [msg] = Professionals.list_messages(nutritionist.id, client.id)
    assert msg.sender_user_id == client.id
  end

  test "opening /messages marks the nutritionist's messages read", %{conn: conn, client: client} do
    nutritionist = with_nutritionist(client)
    {:ok, _} = Professionals.send_message(nutritionist.id, client.id, nutritionist.id, "Welcome!")

    assert Professionals.count_unread_messages_for(client.id) == 1

    {:ok, _view, html} = live(conn, "/messages")
    assert html =~ "Welcome!"
    assert Professionals.count_unread_messages_for(client.id) == 0
  end
end
