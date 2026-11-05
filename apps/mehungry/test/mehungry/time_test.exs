defmodule Mehungry.TimeTest do
  use ExUnit.Case, async: true

  alias Mehungry.Time, as: MT

  describe "tz/1" do
    test "reads an IANA string from a profile-like map" do
      assert MT.tz(%{timezone: "Europe/Athens"}) == "Europe/Athens"
    end

    test "accepts a raw string" do
      assert MT.tz("America/New_York") == "America/New_York"
    end

    test "falls back to Etc/UTC for nil / blank / missing" do
      assert MT.tz(nil) == "Etc/UTC"
      assert MT.tz("") == "Etc/UTC"
      assert MT.tz(%{timezone: nil}) == "Etc/UTC"
      assert MT.tz(%{}) == "Etc/UTC"
    end
  end

  describe "to_utc/2 (local wall-clock -> UTC)" do
    test "Athens winter is +02:00" do
      assert MT.to_utc(~N[2026-01-15 09:00:00], "Europe/Athens") == ~N[2026-01-15 07:00:00]
    end

    test "Athens summer (DST) is +03:00" do
      assert MT.to_utc(~N[2026-07-15 09:00:00], "Europe/Athens") == ~N[2026-07-15 06:00:00]
    end

    test "unknown / blank zone is treated as UTC (identity)" do
      assert MT.to_utc(~N[2026-07-15 09:00:00], "Not/AZone") == ~N[2026-07-15 09:00:00]
      assert MT.to_utc(~N[2026-07-15 09:00:00], nil) == ~N[2026-07-15 09:00:00]
    end
  end

  describe "to_local/2 (UTC -> local wall-clock)" do
    test "inverts to_utc across DST boundaries" do
      for naive <- [~N[2026-01-15 09:00:00], ~N[2026-07-15 09:00:00], ~N[2026-03-29 12:30:00]] do
        assert naive |> MT.to_utc("Europe/Athens") |> MT.to_local("Europe/Athens") == naive
      end
    end

    test "Athens summer UTC 06:00 renders as 09:00 local" do
      assert MT.to_local(~N[2026-07-15 06:00:00], "Europe/Athens") == ~N[2026-07-15 09:00:00]
    end
  end

  describe "DST edge cases" do
    test "spring-forward gap resolves forward to a valid instant (round-trips to UTC)" do
      # 2026-03-29 03:00 EET -> 04:00 EEST in Athens; 03:30 local does not exist.
      utc = MT.to_utc(~N[2026-03-29 03:30:00], "Europe/Athens")
      assert %NaiveDateTime{} = utc
      # The chosen instant, rendered back, is a real local wall-clock time.
      assert %NaiveDateTime{} = MT.to_local(utc, "Europe/Athens")
    end

    test "fall-back overlap resolves to the standard-offset instant (matches Postgres)" do
      # 2026-10-25 in Athens: 04:00 EEST -> 03:00 EET; 03:30 local occurs twice.
      # Standard-offset (+02:00 EET) instant -> 01:30 UTC, matching the migration's
      # Postgres `AT TIME ZONE` conversion.
      assert MT.to_utc(~N[2026-10-25 03:30:00], "Europe/Athens") == ~N[2026-10-25 01:30:00]
    end
  end

  describe "local_today/1 and local_now/1" do
    test "return a Date / NaiveDateTime and tolerate a bad zone" do
      assert %Date{} = MT.local_today("Europe/Athens")
      assert %NaiveDateTime{} = MT.local_now("Europe/Athens")
      assert %Date{} = MT.local_today("Not/AZone")
      assert %NaiveDateTime{} = MT.local_now(nil)
    end
  end
end
