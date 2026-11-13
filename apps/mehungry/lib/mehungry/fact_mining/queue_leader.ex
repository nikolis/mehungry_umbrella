defmodule Mehungry.FactMining.QueueLeader do
  @moduledoc """
  **Cluster-wide single-execution gate for the `:fact_mining` Oban queue.**

  The biomed-fact-miner workers (`SpeciesFactMiningWorker`,
  `ConditionFactMiningWorker`) must run **one at a time across the whole cluster**:
  a single `/mine` call is slow (up to ~10 min) and the miner enforces its own
  concurrency limit. The queue's `limit: 1` is only **per node**, and production
  runs 2 Fly machines (`min_machines_running = 2`), so without a gate two calls
  could fire at once.

  The queue starts **paused** on every node (see the `:fact_mining` queue config).
  This GenServer runs on each node and, on boot and every #{div(20_000, 1000)}s,
  checks Oban leadership and toggles the **local** queue: resume on the leader,
  keep paused everywhere else. The leader's single slot then serializes mining
  naturally (jobs wait in `available`, no snooze churn). We reuse Oban's existing
  **Database** peer leadership lease — DB-based, so it works even though the Fly
  machines are not Erlang-clustered — rather than building a second lock. On a
  leadership change the new leader resumes within one tick; an in-flight job on the
  old leader finishes (pause never kills a running job) or, if that node died, is
  rescued by `Oban.Plugins.Lifeline` and re-run (mining is idempotent).

  Not started under the test Oban config (`testing: :manual`, queues not running) —
  see `Mehungry.Application`.
  """

  use GenServer

  require Logger

  @queue :fact_mining
  @interval_ms 20_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Reconcile immediately, then on a fixed interval.
    {:ok, schedule(), {:continue, :reconcile}}
  end

  @impl true
  def handle_continue(:reconcile, state) do
    reconcile()
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconcile, _state) do
    reconcile()
    {:noreply, schedule()}
  end

  defp schedule do
    Process.send_after(self(), :reconcile, @interval_ms)
  end

  # Resume the queue locally when this node is the Oban leader, otherwise keep it
  # paused. Both calls are idempotent (resuming a running queue / pausing a paused
  # one is a no-op). Tolerate transient Oban errors so a blip can't crash the loop.
  defp reconcile do
    if leader?() do
      safe(fn -> Oban.resume_queue(queue: @queue, local_only: true) end)
    else
      safe(fn -> Oban.pause_queue(queue: @queue, local_only: true) end)
    end
  end

  defp leader? do
    Oban.Peer.leader?(Oban)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp safe(fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.debug("[FactMining.QueueLeader] queue toggle failed: #{inspect(error)}")
      :ok
  catch
    _, reason ->
      Logger.debug("[FactMining.QueueLeader] queue toggle failed: #{inspect(reason)}")
      :ok
  end
end
