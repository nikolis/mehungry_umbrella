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

    %{conn: log_in_user(conn, attacker), appt: appt, attacker: attacker}
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

  test "the day agenda is an always-visible pane; selecting a day updates it",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/nutritionist/appointments")

    # The console always shows the triage rail and the agenda — no modal needed.
    assert html =~ "Needs you"
    assert html =~ "06:00"

    html =
      render_click(view, "select_date", %{"date" => Date.to_iso8601(Date.add(Date.utc_today(), 3))})

    # Day modal shows an hourly agenda with its "+ New" affordance.
    assert html =~ "+ New"
    # The hour labels of the 06:00–22:00 agenda are rendered.
    assert html =~ "06:00"
    assert html =~ "22:00" or html =~ "21:00"
  end

  test "shows a Connect Google Calendar prompt when not connected", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist/appointments")
    assert html =~ "Connect Google Calendar"
  end

  test "shows the connected state once a Google Calendar is linked", %{conn: conn, attacker: attacker} do
    {:ok, _} =
      Professionals.connect_google_calendar(attacker.id, %{
        "access_token" => "ya29.x",
        "refresh_token" => "1//r",
        "expires_in" => 3600,
        "scope" => "calendar"
      })

    {:ok, _view, html} = live(conn, "/nutritionist/appointments")
    assert html =~ "Google Calendar synced"
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

  describe "log measurement" do
    setup %{attacker: attacker} do
      client = Mehungry.AccountsFixtures.user_fixture()

      {:ok, appt} =
        Professionals.create_appointment(%{
          professional_id: attacker.id,
          client_id: client.id,
          scheduled_at: ~N[2099-02-01 10:00:00],
          ends_at: ~N[2099-02-01 11:00:00],
          title: "My consultation",
          status: "accepted"
        })

      %{own_appt: appt, measured_client: client}
    end

    test "logs a measurement linked to the appointment, auto-filling BMI/BMR", %{
      conn: conn,
      attacker: attacker,
      own_appt: appt,
      measured_client: client
    } do
      # Pre-create the client file + an intake so BMI/BMR can be derived.
      {:ok, record} = Professionals.ensure_client_record(attacker.id, client)

      {:ok, _intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "assessed_on" => "2026-01-01",
          "height_m" => "1.70",
          "sex" => "female",
          "age" => "34"
        })

      {:ok, view, _html} = live(conn, "/nutritionist/appointments")

      html = render_click(view, "edit_appointment", %{"id" => to_string(appt.id)})
      assert html =~ "Log measurement"

      render_click(view, "log_measurement", %{"id" => to_string(appt.id)})

      render_submit(view, "save_measurement", %{
        "consultation_note" => %{
          "visit_date" => "2099-02-01",
          "weight_kg" => "72",
          "body_fat_percentage" => "28"
        }
      })

      note =
        Professionals.ConsultationNote
        |> Repo.get_by(appointment_id: appt.id)

      assert note
      assert note.professional_client_id == record.id
      assert note.weight_kg == 72.0
      assert note.body_fat_percentage == 28.0
      assert note.bmi == 24.9
      assert note.bmr_kcal == 1452
    end

    test "hides Log measurement for an external-client appointment", %{
      conn: conn,
      attacker: attacker
    } do
      {:ok, external} =
        Professionals.create_appointment(%{
          professional_id: attacker.id,
          external_client_name: "Walk-in",
          scheduled_at: ~N[2099-03-01 10:00:00],
          ends_at: ~N[2099-03-01 11:00:00],
          title: "External",
          status: "accepted"
        })

      {:ok, view, _html} = live(conn, "/nutritionist/appointments")
      html = render_click(view, "edit_appointment", %{"id" => to_string(external.id)})

      refute html =~ "Log measurement"
    end
  end

  describe "non-UTC professional (Europe/Athens)" do
    setup %{conn: conn} do
      tz = "Europe/Athens"
      pro = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _} = Subscriptions.upsert_subscription(pro.id, %{tier: "pro", status: "active"})

      {:ok, _profile} =
        Professionals.create_professional_profile(%{
          user_id: pro.id,
          specialization: "Dietitian",
          display_name: "Maria Athens",
          timezone: tz
        })

      %{conn: log_in_user(conn, pro), pro: pro, tz: tz}
    end

    test "renders a stored-UTC appointment in the professional's local time", %{
      conn: conn,
      pro: pro,
      tz: tz
    } do
      client = Mehungry.AccountsFixtures.user_fixture()
      local_date = %{Mehungry.Time.local_today(tz) | day: 15}
      utc_sched = Mehungry.Time.to_utc(NaiveDateTime.new!(local_date, ~T[09:30:00]), tz)

      {:ok, _appt} =
        Professionals.create_appointment(%{
          professional_id: pro.id,
          client_id: client.id,
          scheduled_at: utc_sched,
          ends_at: Mehungry.Time.to_utc(NaiveDateTime.new!(local_date, ~T[10:30:00]), tz),
          title: "Athens consult",
          status: "accepted"
        })

      # Stored value really is offset from the 09:30 the professional sees.
      refute NaiveDateTime.to_time(utc_sched) == ~T[09:30:00]

      {:ok, view, _html} = live(conn, "/nutritionist/appointments")
      html = render_click(view, "select_date", %{"date" => Date.to_iso8601(local_date)})

      # 09:30 is not an hourly gridline label, so it can only come from the block.
      assert html =~ "09:30"
      assert html =~ "Athens consult"
    end

    test "manual create converts the entered local time to stored UTC", %{
      conn: conn,
      tz: tz
    } do
      local_date = %{Mehungry.Time.local_today(tz) | day: 16}
      {:ok, view, _html} = live(conn, "/nutritionist/appointments")

      render_submit(view, "save_appointment", %{
        "appointment" => %{
          "external_client_name" => "Walk-in",
          "title" => "Local 14:00 booking",
          "date" => Date.to_iso8601(local_date),
          "start_hour" => "14",
          "start_minute" => "0",
          "end_hour" => "15",
          "end_minute" => "0"
        }
      })

      appt = Repo.get_by(Professionals.Appointment, title: "Local 14:00 booking")
      assert appt
      assert appt.scheduled_at == Mehungry.Time.to_utc(NaiveDateTime.new!(local_date, ~T[14:00:00]), tz)
      assert appt.ends_at == Mehungry.Time.to_utc(NaiveDateTime.new!(local_date, ~T[15:00:00]), tz)
    end
  end
end
