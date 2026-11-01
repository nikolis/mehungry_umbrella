defmodule MehungryWeb.SessionMetricsTest do
  @moduledoc """
  End-to-end check that the `MehungryWeb.SessionMetrics` `on_mount` hook (wired
  into every live_session in the router) registers a connected LiveView with the
  `Mehungry.Meta.SessionAggregator`, that a genuine interaction (the
  `"mh:visit_engaged"` event) qualifies the visit, and that it is folded into the
  anonymous daily counter when finalized — all without any cookie-consent being
  accepted (the deliberate difference from Visit tracking).
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Meta
  alias Mehungry.Meta.SessionAggregator

  test "an engaged public visit is counted on finalization", %{conn: conn} do
    # The aggregator's DB write is disabled by default in the suite (see
    # config/test.exs, which stops stray cross-test pollution); this test asserts
    # the end-to-end path, so turn it on just here and restore it after.
    prev = Application.get_env(:mehungry, :session_metrics_recording)
    Application.put_env(:mehungry, :session_metrics_recording, true)
    on_exit(fn -> Application.put_env(:mehungry, :session_metrics_recording, prev) end)

    before = Meta.session_metrics_today().sessions

    # Trap exits so the view (and its LiveViewTest proxy) dying doesn't take the
    # test — and thus the sandbox owner — down with it.
    Process.flag(:trap_exit, true)

    # /trial is in live_session :default3 — public, no consent accepted.
    {:ok, lv, _html} = live(conn, "/trial")

    # Simulate a genuine interaction (the VisitEngagement hook pushes this) so the
    # visit qualifies — a bare mount+close is now correctly NOT counted.
    render_hook(lv, "mh:visit_engaged", %{})

    # Closing the LiveView process fires the aggregator's :DOWN handler.
    ref = Process.monitor(lv.pid)
    Process.exit(lv.pid, :shutdown)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000

    # DOWN no longer records directly — finalize the now-idle visit.
    assert :ok = SessionAggregator.flush()

    assert eventually(fn -> Meta.session_metrics_today().sessions > before end),
           "expected the anonymous visit counter to increment after the engaged visit closed"
  end

  defp eventually(fun, retries \\ 50) do
    cond do
      fun.() -> true
      retries <= 0 -> false
      true -> Process.sleep(20) && eventually(fun, retries - 1)
    end
  end
end
