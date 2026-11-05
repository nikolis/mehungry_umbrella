defmodule Mehungry.Repo.Migrations.ConvertAppointmentTimesToUtc do
  use Ecto.Migration

  @moduledoc """
  One-time backfill: appointment `scheduled_at`/`ends_at` were historically
  stored as the professional's **local wall-clock** naive datetime. The codebase
  now treats these columns as canonical **UTC**. Reinterpret each existing row's
  times as its professional's local time and convert to UTC via Postgres
  `AT TIME ZONE` (DST-correct per row).

  Rows whose professional has no timezone (or `Etc/UTC`) are left unchanged — for
  them local == UTC already. Postgres's `AT TIME ZONE` resolves a fall-back
  overlap to the standard offset, matching `Mehungry.Time` (the live write path).

  DEPLOY ORDERING: this must run as part of the same release that switches writes
  to UTC. Rows written after the code deploys are already UTC; running this
  migration after such writes exist would double-convert them. Run once, at
  release time, before new bookings are taken.
  """

  # Convert only rows for professionals with a real, non-UTC timezone.
  @where """
  FROM professional_profiles p
  WHERE p.user_id = professional_appointments.professional_id
    AND p.timezone IS NOT NULL
    AND p.timezone <> ''
    AND p.timezone <> 'Etc/UTC'
  """

  def up do
    execute("""
    UPDATE professional_appointments
    SET scheduled_at = (professional_appointments.scheduled_at AT TIME ZONE p.timezone) AT TIME ZONE 'UTC',
        ends_at = CASE
                    WHEN professional_appointments.ends_at IS NULL THEN NULL
                    ELSE (professional_appointments.ends_at AT TIME ZONE p.timezone) AT TIME ZONE 'UTC'
                  END
    #{@where}
    """)
  end

  def down do
    # Reverse: interpret the stored UTC naive as UTC and render it back to the
    # professional's local wall-clock.
    execute("""
    UPDATE professional_appointments
    SET scheduled_at = (professional_appointments.scheduled_at AT TIME ZONE 'UTC') AT TIME ZONE p.timezone,
        ends_at = CASE
                    WHEN professional_appointments.ends_at IS NULL THEN NULL
                    ELSE (professional_appointments.ends_at AT TIME ZONE 'UTC') AT TIME ZONE p.timezone
                  END
    #{@where}
    """)
  end
end
