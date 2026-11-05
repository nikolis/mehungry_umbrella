defmodule MehungryWeb.MyNutritionistLive.IndexTest do
  @moduledoc """
  Smoke + state tests for the client "My nutritionist" hub: the connected state
  shows ONLY the connected nutritionist (no directory search, no invitations from
  others), the unconnected state shows an empty-state prompt + a link to the full
  directory (no inline search/list), and a client connected to a professional
  with no published public profile still sees that nutritionist.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Professionals
  alias Mehungry.Professionals.TutorClientAssignment
  alias Mehungry.Repo

  setup :register_and_log_in_user

  defp assign_nutritionist(client, professional) do
    %TutorClientAssignment{}
    |> TutorClientAssignment.changeset(%{professional_id: professional.id, client_id: client.id})
    |> Repo.insert!()
  end

  test "unconnected: shows an empty-state prompt + directory link, not a search/list",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/en/my-nutritionist")

    assert html =~ "not connected to a nutritionist yet"
    assert html =~ "Browse the full directory"
    # No inline directory search/list on this screen anymore.
    refute html =~ ~s(name="q")
  end

  test "connected with a public profile: shows the nutritionist, no directory search",
       %{conn: conn, user: client} do
    professional = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _profile} =
      Professionals.create_professional_profile(%{
        user_id: professional.id,
        display_name: "Dr. Elena Papad-Test",
        specialization: "Sports nutrition",
        city: "Athens",
        bio: "Helping clients eat well, backed by USDA data.",
        is_public: true
      })

    assign_nutritionist(client, professional)

    {:ok, _view, html} = live(conn, "/en/my-nutritionist")

    assert html =~ "Your nutritionist"
    assert html =~ "Dr. Elena Papad-Test"
    assert html =~ "View full profile"
    # The directory search must NOT appear for a connected client.
    refute html =~ "Browse the full directory"
  end

  test "connected with open availability: can book an appointment from this screen",
       %{conn: conn, user: client} do
    professional = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _profile} =
      Professionals.create_professional_profile(%{
        user_id: professional.id,
        display_name: "Dr. Bookable",
        specialization: "Sports nutrition",
        city: "Athens",
        bio: "Helping clients eat well, backed by USDA data.",
        is_public: true
      })

    # A full week of 09:00–11:00 availability → future bookable slots.
    {:ok, _} =
      Professionals.replace_availabilities(
        professional.id,
        for(dow <- 0..6, do: %{day_of_week: dow, start_time: ~T[09:00:00], end_time: ~T[11:00:00]})
      )

    assign_nutritionist(client, professional)

    {:ok, view, html} = live(conn, "/en/my-nutritionist")

    assert html =~ "Book an appointment"

    today = Date.utc_today()
    [slot | _] = Professionals.available_slots(professional.id, today, Date.add(today, 30))
    date = slot |> NaiveDateTime.to_date() |> Date.to_iso8601()

    view
    |> element(~s|button[phx-click="select_booking_date"][phx-value-date="#{date}"]|)
    |> render_click()

    view
    |> element(
      ~s|button[phx-click="select_booking_slot"][phx-value-at="#{NaiveDateTime.to_iso8601(slot)}"]|
    )
    |> render_click()

    html =
      view
      |> element(~s|form[phx-submit="confirm_booking"]|)
      |> render_submit(%{"notes" => ""})

    assert html =~ "Request sent!"

    appt =
      Repo.get_by(Professionals.Appointment,
        professional_id: professional.id,
        client_id: client.id
      )

    assert appt.status == "requested"
    assert appt.scheduled_at == slot
  end

  test "connected without a published profile: still shows the nutritionist, never the directory",
       %{conn: conn, user: client} do
    professional = Mehungry.AccountsFixtures.user_fixture()
    assign_nutritionist(client, professional)

    {:ok, _view, html} = live(conn, "/en/my-nutritionist")

    assert html =~ "Your nutritionist"
    assert html =~ (professional.name || professional.email)
    refute html =~ "Browse the full directory"
  end

  test "connected: the message thread is embedded on the hub — opening reads the nutritionist's messages, and the client can reply",
       %{conn: conn, user: client} do
    professional = Mehungry.AccountsFixtures.user_fixture()
    professional = Repo.update!(Ecto.Changeset.change(professional, name: "Dr. Nutri"))
    assign_nutritionist(client, professional)

    {:ok, _} = Professionals.send_message(professional.id, client.id, professional.id, "Welcome!")
    assert Professionals.count_unread_messages_for(client.id) == 1

    {:ok, view, html} = live(conn, "/en/my-nutritionist")

    # The thread is embedded here (no standalone /messages page); opening the hub
    # shows the nutritionist's message and marks it read.
    assert html =~ "Welcome!"
    assert Professionals.count_unread_messages_for(client.id) == 0

    html =
      view
      |> form("form[phx-submit='send_message']", %{body: "Thanks, I have a question"})
      |> render_submit()

    assert html =~ "Thanks, I have a question"
    assert [_welcome, reply] = Professionals.list_messages(professional.id, client.id)
    assert reply.sender_user_id == client.id
  end

  test "unconnected: no message thread is shown", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/en/my-nutritionist")
    refute html =~ "send_message"
  end

  test "connected client can disconnect from their nutritionist",
       %{conn: conn, user: client} do
    professional = Mehungry.AccountsFixtures.user_fixture()
    assign_nutritionist(client, professional)

    {:ok, view, html} = live(conn, "/en/my-nutritionist")
    assert html =~ "Disconnect"

    html = render_click(view, "unlink_nutritionist")

    # The assignment is gone and the hub falls back to the unconnected empty state.
    refute Professionals.get_assignment_for_client(client.id)
    assert html =~ "not connected to a nutritionist yet"
  end
end
