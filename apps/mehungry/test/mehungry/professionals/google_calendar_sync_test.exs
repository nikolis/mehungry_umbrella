defmodule Mehungry.Professionals.GoogleCalendarSyncTest do
  use Mehungry.DataCase, async: false

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals
  alias Mehungry.ObanWorkers.{AppointmentCalendarSyncWorker, GoogleCalendarBusyImportWorker}

  setup do
    Application.put_env(:mehungry, :gcal_stub_pid, self())

    on_exit(fn ->
      Application.delete_env(:mehungry, :gcal_stub_pid)

      for name <- ~w(refresh_access_token insert_event update_event delete_event free_busy)a do
        Application.delete_env(:mehungry, :"gcal_stub_#{name}")
      end
    end)

    professional = user_fixture()
    client = user_fixture()

    rows = for dow <- 0..6, do: %{day_of_week: dow, start_time: ~T[09:00:00], end_time: ~T[11:00:00]}
    {:ok, _} = Professionals.replace_availabilities(professional.id, rows)

    %{professional: professional, client: client}
  end

  # A non-expiring connected Google account (so ensure_fresh_token skips refresh).
  defp connect(professional) do
    {:ok, account} =
      Professionals.connect_google_calendar(professional.id, %{
        "access_token" => "ya29.live",
        "refresh_token" => "1//refresh",
        "expires_in" => 3600,
        "scope" => "calendar"
      })

    account
  end

  defp accepted_appointment(ctx, opts \\ []) do
    scheduled_at = Keyword.get(opts, :scheduled_at, ~N[2099-01-05 09:00:00])

    {:ok, appt} =
      Professionals.create_appointment(%{
        professional_id: ctx.professional.id,
        client_id: ctx.client.id,
        scheduled_at: scheduled_at,
        ends_at: NaiveDateTime.add(scheduled_at, 3600),
        title: "Consultation",
        status: "accepted"
      })

    appt
  end

  # ── Slot engine: busy intervals block overlapping slots ─────────────────────

  test "available_slots drops slots overlapping a cached busy interval", ctx do
    date = Date.add(Date.utc_today(), 7)
    busy_start = DateTime.new!(date, ~T[09:00:00], "Etc/UTC")
    busy_end = DateTime.new!(date, ~T[10:00:00], "Etc/UTC")

    {:ok, 1} =
      Professionals.replace_calendar_busy(ctx.professional.id, [
        %{starts_at: busy_start, ends_at: busy_end}
      ])

    slots = Professionals.available_slots(ctx.professional.id, date, date)
    times = Enum.map(slots, &NaiveDateTime.to_time/1)

    refute ~T[09:00:00] in times, "09:00 overlaps busy and must be hidden"
    assert ~T[10:00:00] in times, "10:00 is free and must remain bookable"
  end

  test "with no busy intervals both availability slots are offered", ctx do
    date = Date.add(Date.utc_today(), 7)
    slots = Professionals.available_slots(ctx.professional.id, date, date)
    times = Enum.map(slots, &NaiveDateTime.to_time/1)

    assert ~T[09:00:00] in times
    assert ~T[10:00:00] in times
  end

  # ── Push sync (app → Google) ────────────────────────────────────────────────

  test "upsert pushes a new event and stores google_event_id + Meet URL", ctx do
    connect(ctx.professional)
    appt = accepted_appointment(ctx)

    assert :ok =
             AppointmentCalendarSyncWorker.perform(%Oban.Job{
               args: %{"appointment_id" => appt.id, "action" => "upsert"}
             })

    assert_received {:gcal, :insert_event, {"ya29.live", "primary", _event}}

    updated = Professionals.get_appointment!(appt.id)
    assert updated.google_event_id == "evt_stub_123"
    assert updated.meeting_url == "https://meet.google.com/stub-abc-def"
  end

  test "upsert on an already-synced appointment patches instead of inserting", ctx do
    connect(ctx.professional)
    appt = accepted_appointment(ctx)
    {:ok, appt} = Professionals.put_appointment_google_event(appt, "evt_existing", "https://meet/existing")

    assert :ok =
             AppointmentCalendarSyncWorker.perform(%Oban.Job{
               args: %{"appointment_id" => appt.id, "action" => "upsert"}
             })

    assert_received {:gcal, :update_event, {"ya29.live", "primary", "evt_existing", _event}}
    refute_received {:gcal, :insert_event, _}
  end

  test "delete removes the pushed event", ctx do
    connect(ctx.professional)
    appt = accepted_appointment(ctx)
    {:ok, appt} = Professionals.put_appointment_google_event(appt, "evt_del", nil)

    assert :ok =
             AppointmentCalendarSyncWorker.perform(%Oban.Job{
               args: %{"appointment_id" => appt.id, "action" => "delete"}
             })

    assert_received {:gcal, :delete_event, {"ya29.live", "primary", "evt_del"}}
  end

  test "a Google error on upsert is swallowed (best-effort) — job still succeeds", ctx do
    connect(ctx.professional)
    appt = accepted_appointment(ctx)

    Application.put_env(:mehungry, :gcal_stub_insert_event, fn _ ->
      {:error, {:http_error, 403, "forbidden"}}
    end)

    assert :ok =
             AppointmentCalendarSyncWorker.perform(%Oban.Job{
               args: %{"appointment_id" => appt.id, "action" => "upsert"}
             })

    # No event id stored — the manual meeting_url path still covers the user.
    assert Professionals.get_appointment!(appt.id).google_event_id == nil
  end

  test "upsert is a no-op when the nutritionist has no connected calendar", ctx do
    appt = accepted_appointment(ctx)

    assert :ok =
             AppointmentCalendarSyncWorker.perform(%Oban.Job{
               args: %{"appointment_id" => appt.id, "action" => "upsert"}
             })

    refute_received {:gcal, :insert_event, _}
    assert Professionals.get_appointment!(appt.id).google_event_id == nil
  end

  # ── Busy import (Google → app) ──────────────────────────────────────────────

  test "busy import caches the intervals free_busy returns", ctx do
    connect(ctx.professional)

    busy = [
      %{"start" => "2099-01-05T09:00:00Z", "end" => "2099-01-05T10:00:00Z"},
      %{"start" => "2099-01-06T14:00:00Z", "end" => "2099-01-06T15:00:00Z"}
    ]

    Application.put_env(:mehungry, :gcal_stub_free_busy, fn _ -> {:ok, busy} end)

    assert :ok =
             GoogleCalendarBusyImportWorker.perform(%Oban.Job{
               args: %{"professional_id" => ctx.professional.id}
             })

    cached =
      Professionals.list_calendar_busy(
        ctx.professional.id,
        ~N[2099-01-01 00:00:00],
        ~N[2099-01-31 00:00:00]
      )

    assert length(cached) == 2
  end
end
