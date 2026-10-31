defmodule Mehungry.MetaTest do
  use Mehungry.DataCase

  alias Mehungry.Meta

  describe "anonymous session metrics" do
    alias Mehungry.Meta.SessionAggregator

    test "record_session/2 upserts and accumulates into today's bucket" do
      now = DateTime.utc_now()

      assert :ok = Meta.record_session(now, 10)
      assert :ok = Meta.record_session(now, 20)

      assert %{sessions: 2, total_seconds: 30, avg_seconds: 15} = Meta.session_metrics_today()
    end

    test "session_metrics_today/0 is zeroed when nothing recorded" do
      assert %{sessions: 0, total_seconds: 0, avg_seconds: 0} = Meta.session_metrics_today()
    end

    test "session_metrics_per_day/1 returns today's row with a computed average" do
      now = DateTime.utc_now()
      Meta.record_session(now, 30)
      Meta.record_session(now, 10)

      rows = Meta.session_metrics_per_day(14)
      today_local = today_in_reporting_tz()

      assert %{session_count: 2, total_duration_seconds: 40, avg_seconds: 20} =
               Enum.find(rows, &(&1.date == today_local))
    end

    test "SessionAggregator counts a tracked process when it exits" do
      # This test exercises the aggregator's DB write, which the suite disables by
      # default (see config/test.exs); turn it back on just for this test.
      enable_session_recording()
      before = Meta.session_metrics_today().sessions

      # A throwaway process standing in for a connected LiveView.
      {pid, ref} = spawn_monitor(fn -> Process.sleep(:infinity) end)
      SessionAggregator.track(pid)
      # Give the cast time to register the monitor before we kill the process.
      Process.sleep(20)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _, _}, 1_000

      assert eventually(fn -> Meta.session_metrics_today().sessions > before end)
    end
  end

  # Re-enable the aggregator's DB write for a single test (restored after it).
  defp enable_session_recording do
    prev = Application.get_env(:mehungry, :session_metrics_recording)
    Application.put_env(:mehungry, :session_metrics_recording, true)
    on_exit(fn -> Application.put_env(:mehungry, :session_metrics_recording, prev) end)
  end

  defp today_in_reporting_tz do
    %{rows: [[date]]} =
      Mehungry.Repo.query!("SELECT (now() AT TIME ZONE $1)::date", [Meta.reporting_timezone()])

    date
  end

  defp eventually(fun, retries \\ 50) do
    cond do
      fun.() -> true
      retries <= 0 -> false
      true -> Process.sleep(20) && eventually(fun, retries - 1)
    end
  end
end
