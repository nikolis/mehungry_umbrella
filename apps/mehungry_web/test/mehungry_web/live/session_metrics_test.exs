defmodule MehungryWeb.SessionMetricsTest do
  @moduledoc """
  End-to-end check that the `MehungryWeb.SessionMetrics` `on_mount` hook (wired
  into every live_session in the router) registers a connected LiveView with the
  `Mehungry.Meta.SessionAggregator`, and that the aggregator folds the process
  lifetime into the anonymous daily counter when the process dies — all without
  any cookie-consent being accepted (the deliberate difference from Visit tracking).
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Meta

  test "mounting a public LiveView counts an anonymous session on disconnect", %{conn: conn} do
    before = Meta.session_metrics_today().sessions

    # Trap exits so the view (and its LiveViewTest proxy) dying doesn't take the
    # test — and thus the sandbox owner — down with it.
    Process.flag(:trap_exit, true)

    # /trial is in live_session :default3 — public, no consent accepted.
    {:ok, lv, _html} = live(conn, "/trial")

    # Closing the LiveView process fires the aggregator's :DOWN handler.
    ref = Process.monitor(lv.pid)
    Process.exit(lv.pid, :shutdown)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000

    assert eventually(fn -> Meta.session_metrics_today().sessions > before end),
           "expected the anonymous session counter to increment after the LiveView closed"
  end

  defp eventually(fun, retries \\ 50) do
    cond do
      fun.() -> true
      retries <= 0 -> false
      true -> Process.sleep(20) && eventually(fun, retries - 1)
    end
  end
end
