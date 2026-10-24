defmodule MehungryWeb.NutritionistLive.AppointmentCalendarTest do
  @moduledoc """
  Access-control regression tests for the nutritionist appointment calendar:
  a nutritionist must never be able to mutate another nutritionist's
  appointments by posting a crafted appointment id (IDOR).
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo, Subscriptions}

  setup %{conn: conn} do
    attacker = Mehungry.AccountsFixtures.user_fixture()
    victim = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()

    for n <- [attacker, victim] do
      {:ok, _} = Subscriptions.upsert_subscription(n.id, %{tier: "pro", status: "active"})
    end

    # An appointment owned by the victim nutritionist, currently requested.
    {:ok, appt} =
      Professionals.create_appointment(%{
        professional_id: victim.id,
        client_id: client.id,
        scheduled_at: ~N[2099-01-01 10:00:00],
        ends_at: ~N[2099-01-01 11:00:00],
        title: "Victim's consultation",
        status: "requested"
      })

    %{conn: log_in_user(conn, attacker), appt: appt}
  end

  test "cannot delete another nutritionist's appointment", %{conn: conn, appt: appt} do
    {:ok, view, _html} = live(conn, "/nutritionist/appointments")

    render_click(view, "delete_appointment", %{"id" => to_string(appt.id)})

    assert Repo.get(Professionals.Appointment, appt.id)
    assert render(view) =~ "Appointment not found."
  end

  test "cannot accept another nutritionist's appointment", %{conn: conn, appt: appt} do
    {:ok, view, _html} = live(conn, "/nutritionist/appointments")

    render_click(view, "accept_appointment", %{"appointment_id" => to_string(appt.id)})

    assert Repo.get(Professionals.Appointment, appt.id).status == "requested"
    assert render(view) =~ "Appointment not found."
  end

  test "cannot decline another nutritionist's appointment", %{conn: conn, appt: appt} do
    {:ok, view, _html} = live(conn, "/nutritionist/appointments")

    render_click(view, "decline_appointment", %{"id" => to_string(appt.id)})

    assert Repo.get(Professionals.Appointment, appt.id).status == "requested"
  end

  test "cannot re-home another nutritionist's appointment via edit+save", %{
    conn: conn,
    appt: appt
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/appointments")

    # Edit is refused, so editing_appointment is never set and a subsequent save
    # cannot reassign the victim's appointment to the attacker.
    render_click(view, "edit_appointment", %{"id" => to_string(appt.id)})

    assert render(view) =~ "Appointment not found."
    assert Repo.get(Professionals.Appointment, appt.id).professional_id == appt.professional_id
  end

  test "junk appointment ids are rejected without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/nutritionist/appointments")

    render_click(view, "delete_appointment", %{"id" => "not-a-number"})

    assert render(view) =~ "Appointment not found."
  end

  test "cannot manually create an appointment for a user who is not your client",
       %{conn: conn} do
    stranger = Mehungry.AccountsFixtures.user_fixture()
    {:ok, view, _html} = live(conn, "/nutritionist/appointments")

    before = Repo.aggregate(Professionals.Appointment, :count)

    render_submit(view, "save_appointment", %{
      "appointment" => %{
        "client_id" => to_string(stranger.id),
        "title" => "Sneaky",
        "date" => Date.to_iso8601(Date.add(Date.utc_today(), 3)),
        "start_hour" => "9",
        "start_minute" => "0",
        "end_hour" => "10",
        "end_minute" => "0"
      }
    })

    assert render(view) =~ "Select one of your own clients."
    assert Repo.aggregate(Professionals.Appointment, :count) == before
  end
end
