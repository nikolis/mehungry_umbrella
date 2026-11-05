defmodule Mehungry.Time do
  @moduledoc """
  Timezone conversions for appointment times.

  Appointments are stored as **UTC** naive datetimes (the `:naive_datetime`
  columns `scheduled_at`/`ends_at` hold a UTC wall-clock instant). The
  professional's `profile.timezone` (an IANA name, e.g. `"Europe/Athens"`) is the
  lens that turns those stored UTC values into the local wall-clock the
  nutritionist and their clients actually think in — and the reverse, when a
  local time from a form or an availability window is written.

  Every conversion routes through here so the DST gap/overlap policy and the
  default-timezone fallback live in exactly one place.

  Policy:
    * Unknown / blank timezone → `"Etc/UTC"` (conversions become identity).
    * Spring-forward gap (a local time that does not exist) → the first valid
      instant after the gap.
    * Fall-back overlap (a local time that occurs twice) → the standard-offset
      (later) instant. This matches Postgres `AT TIME ZONE`, which the one-time
      backfill migration uses, so the live write path and the migration agree.
  """

  @default_tz "Etc/UTC"

  @doc """
  Resolve an IANA timezone string from a profile, a user-like map, or a raw
  string. Falls back to `"Etc/UTC"` for `nil`/blank/unknown input.
  """
  def tz(%{timezone: tz}) when is_binary(tz) and tz != "", do: tz
  def tz(tz) when is_binary(tz) and tz != "", do: tz
  def tz(_), do: @default_tz

  @doc """
  Convert a local wall-clock `NaiveDateTime` (interpreted in `tz`) to the UTC
  `NaiveDateTime` used for storage.
  """
  def to_utc(%NaiveDateTime{} = local, tz) do
    local
    |> resolve_local(normalize(tz))
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end

  @doc """
  Convert a stored UTC `NaiveDateTime` to a zoned `DateTime` in `tz` — use when
  you also need the zone abbreviation (`.zone_abbr`) for display.
  """
  def to_local_dt(%NaiveDateTime{} = utc, tz) do
    utc
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(normalize(tz))
  end

  @doc """
  Convert a stored UTC `NaiveDateTime` to the local wall-clock `NaiveDateTime`
  in `tz`.
  """
  def to_local(%NaiveDateTime{} = utc, tz) do
    utc |> to_local_dt(tz) |> DateTime.to_naive()
  end

  @doc "Today's date in `tz` (falls back to the UTC date on an unknown zone)."
  def local_today(tz) do
    DateTime.now!(normalize(tz)) |> DateTime.to_date()
  rescue
    _ -> Date.utc_today()
  end

  @doc "The current local wall-clock `NaiveDateTime` in `tz`."
  def local_now(tz) do
    DateTime.now!(normalize(tz)) |> DateTime.to_naive()
  rescue
    _ -> NaiveDateTime.utc_now()
  end

  # Fall back to UTC for any zone the tz database can't resolve, so callers never
  # crash on a bad/legacy profile.timezone value.
  defp normalize(tz) do
    tz = tz(tz)

    case DateTime.now(tz) do
      {:ok, _} -> tz
      _ -> @default_tz
    end
  end

  # DST-safe local -> DateTime. normalize/1 has already guaranteed a resolvable
  # zone, so only :ok / :ambiguous / :gap are possible here.
  defp resolve_local(naive, tz) do
    case DateTime.from_naive(naive, tz) do
      {:ok, dt} -> dt
      {:ambiguous, _first, second} -> second
      {:gap, _just_before, just_after} -> just_after
    end
  end
end
