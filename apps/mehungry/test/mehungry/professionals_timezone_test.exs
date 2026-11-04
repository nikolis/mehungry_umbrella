defmodule Mehungry.ProfessionalsTimezoneTest do
  @moduledoc """
  Appointment times are stored as canonical UTC; the professional's
  `profile.timezone` is the lens. These exercise a non-UTC professional
  (Europe/Athens, +2 winter / +3 summer) — the existing booking tests all use a
  tz-less professional where conversion is the identity and wouldn't catch a
  regression here.
  """
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals

  @tz "Europe/Athens"

  defp athens_professional(windows, slot_minutes \\ 60) do
    user = user_fixture()

    {:ok, _profile} =
      Professionals.create_professional_profile(%{
        user_id: user.id,
        specialization: "Dietitian",
        display_name: "Maria Papadaki",
        timezone: @tz,
        appointment_slot_minutes: slot_minutes
      })

    {:ok, _} = Professionals.replace_availabilities(user.id, windows)
    user
  end

  defp daily(start_t, end_t), do: for(dow <- 0..6, do: %{day_of_week: dow, start_time: start_t, end_time: end_t})

  describe "available_slots returns UTC for local availability windows" do
    setup do
      %{pro: athens_professional(daily(~T[09:00:00], ~T[11:00:00]))}
    end

    test "winter window 09:00/10:00 Athens -> 07:00/08:00 UTC", %{pro: pro} do
      d = ~D[2027-01-20]
      slots = Professionals.available_slots(pro.id, d, d)

      assert ~N[2027-01-20 07:00:00] in slots
      assert ~N[2027-01-20 08:00:00] in slots
    end

    test "summer (DST) window 09:00/10:00 Athens -> 06:00/07:00 UTC", %{pro: pro} do
      d = ~D[2027-07-20]
      slots = Professionals.available_slots(pro.id, d, d)

      assert ~N[2027-07-20 06:00:00] in slots
      assert ~N[2027-07-20 07:00:00] in slots
    end

    test "booking stores the UTC instant and frees it from availability", %{pro: pro} do
      client = user_fixture()
      d = ~D[2027-01-20]
      slot = ~N[2027-01-20 07:00:00]

      assert slot in Professionals.available_slots(pro.id, d, d)

      assert {:ok, appt} = Professionals.request_appointment(pro.id, client.id, slot, title: "C")
      assert appt.scheduled_at == slot
      assert appt.ends_at == ~N[2027-01-20 08:00:00]

      refute slot in Professionals.available_slots(pro.id, d, d)

      assert {:error, :slot_unavailable} =
               Professionals.request_appointment(pro.id, client.id, slot)
    end
  end

  describe "backfill migration (ConvertAppointmentTimesToUtc) UPDATE" do
    # Mirrors priv/repo/migrations/20261104035233_convert_appointment_times_to_utc.exs
    # so a regression in the conversion SQL is caught in CI.
    @backfill_sql """
    UPDATE professional_appointments
    SET scheduled_at = (professional_appointments.scheduled_at AT TIME ZONE p.timezone) AT TIME ZONE 'UTC',
        ends_at = CASE
                    WHEN professional_appointments.ends_at IS NULL THEN NULL
                    ELSE (professional_appointments.ends_at AT TIME ZONE p.timezone) AT TIME ZONE 'UTC'
                  END
    FROM professional_profiles p
    WHERE p.user_id = professional_appointments.professional_id
      AND p.timezone IS NOT NULL AND p.timezone <> '' AND p.timezone <> 'Etc/UTC'
    """

    defp legacy_appt(pro_id, client_id, scheduled_at, ends_at) do
      {:ok, appt} =
        Mehungry.Professionals.create_appointment(%{
          professional_id: pro_id,
          client_id: client_id,
          scheduled_at: scheduled_at,
          ends_at: ends_at,
          title: "Legacy",
          status: "requested"
        })

      appt
    end

    test "converts a non-UTC professional's local rows to UTC and leaves tz-less rows untouched" do
      client = user_fixture()

      # Legacy Athens row stored as local wall-clock (pre-migration behaviour).
      athens = athens_professional(daily(~T[09:00:00], ~T[11:00:00]))
      a = legacy_appt(athens.id, client.id, ~N[2027-01-20 09:00:00], ~N[2027-01-20 10:00:00])

      # Tz-less professional: local == UTC, must be left unchanged.
      utcless = user_fixture()
      {:ok, _} = Mehungry.Professionals.replace_availabilities(utcless.id, daily(~T[09:00:00], ~T[11:00:00]))
      b = legacy_appt(utcless.id, client.id, ~N[2027-01-20 09:00:00], ~N[2027-01-20 10:00:00])

      Mehungry.Repo.query!(@backfill_sql, [])

      a2 = Mehungry.Repo.get!(Mehungry.Professionals.Appointment, a.id)
      b2 = Mehungry.Repo.get!(Mehungry.Professionals.Appointment, b.id)

      assert a2.scheduled_at == ~N[2027-01-20 07:00:00]
      assert a2.ends_at == ~N[2027-01-20 08:00:00]
      assert b2.scheduled_at == ~N[2027-01-20 09:00:00]
      assert b2.ends_at == ~N[2027-01-20 10:00:00]
    end
  end

  describe "slots that straddle the UTC/local midnight boundary" do
    test "an early-morning local window produces a previous-UTC-day slot that is still bookable" do
      # 00:00–02:00 Athens on 2027-01-20 → 22:00–00:00 UTC on 2027-01-19.
      pro = athens_professional(daily(~T[00:00:00], ~T[02:00:00]))
      client = user_fixture()

      slots = Professionals.available_slots(pro.id, ~D[2027-01-20], ~D[2027-01-20])
      assert ~N[2027-01-19 22:00:00] in slots

      # slot_open? regenerates from the UTC date (01-19); the widened ±1-day range
      # must still find the slot whose local source date was 01-20.
      assert {:ok, appt} =
               Professionals.request_appointment(pro.id, client.id, ~N[2027-01-19 22:00:00])

      assert appt.scheduled_at == ~N[2027-01-19 22:00:00]
    end
  end
end
