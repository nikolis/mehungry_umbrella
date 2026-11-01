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

    # These exercise the aggregator's visit/qualification logic against a private
    # instance (not the global named server, which holds stale visits from every
    # LiveView test in the suite — flushing that would pollute these assertions).
    # The DB write is disabled by default (config/test.exs); each test enables it.

    test "a qualifying (engaged) visit is counted once its process exits" do
      enable_session_recording()
      agg = start_aggregator()
      before = Meta.session_metrics_today().sessions

      {pid, ref} = spawn_tracked(agg, "visit-engaged", nil)
      GenServer.cast(agg, {:engaged, pid})
      kill_and_await(pid, ref)

      # DOWN alone no longer records — finalization happens on flush/sweep.
      assert :ok = SessionAggregator.flush(agg)
      assert eventually(fn -> Meta.session_metrics_today().sessions == before + 1 end)
    end

    test "two processes sharing one token fold into a single visit" do
      enable_session_recording()
      agg = start_aggregator()
      before = Meta.session_metrics_today().sessions

      # Same token across two "page" processes = one multi-view visit (views >= 2
      # qualifies it even without an explicit interaction).
      {pid1, ref1} = spawn_tracked(agg, "shared-token", nil)
      {pid2, ref2} = spawn_tracked(agg, "shared-token", nil)
      kill_and_await(pid1, ref1)
      kill_and_await(pid2, ref2)

      assert :ok = SessionAggregator.flush(agg)
      assert eventually(fn -> Meta.session_metrics_today().sessions == before + 1 end)
    end

    test "a single short non-interacting view is dropped" do
      enable_session_recording()
      agg = start_aggregator()
      before = Meta.session_metrics_today().sessions

      # One view, no interaction, ~0s duration — not a real visit.
      {pid, ref} = spawn_tracked(agg, "bounce", nil)
      kill_and_await(pid, ref)

      assert :ok = SessionAggregator.flush(agg)
      # Give any (erroneous) write a chance, then assert the counter did NOT move.
      Process.sleep(60)
      assert Meta.session_metrics_today().sessions == before
    end

    test "a known-bot User-Agent is never tracked" do
      enable_session_recording()
      agg = start_aggregator()
      before = Meta.session_metrics_today().sessions

      {pid, ref} = spawn_tracked(agg, "bot-visit", "Mozilla/5.0 (compatible; Googlebot/2.1)")
      # Even an interaction can't rescue it — it was never tracked.
      GenServer.cast(agg, {:engaged, pid})
      kill_and_await(pid, ref)

      assert :ok = SessionAggregator.flush(agg)
      Process.sleep(60)
      assert Meta.session_metrics_today().sessions == before
    end
  end

  # A private, unnamed aggregator instance so a test's visits are isolated from
  # the global server (and from each other).
  defp start_aggregator do
    {:ok, agg} = GenServer.start_link(Mehungry.Meta.SessionAggregator, :ok)
    on_exit(fn -> if Process.alive?(agg), do: GenServer.stop(agg) end)
    agg
  end

  # Spawns a throwaway process standing in for a connected LiveView and registers
  # it with `agg` under `token`/`user_agent`; returns `{pid, monitor_ref}`.
  defp spawn_tracked(agg, token, user_agent) do
    {pid, ref} = spawn_monitor(fn -> Process.sleep(:infinity) end)
    GenServer.cast(agg, {:track, token, user_agent, pid})
    # Let the track cast register the monitor before the caller kills the process.
    Process.sleep(20)
    {pid, ref}
  end

  defp kill_and_await(pid, ref) do
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
    # Let the aggregator process its own :DOWN before we flush.
    Process.sleep(20)
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
