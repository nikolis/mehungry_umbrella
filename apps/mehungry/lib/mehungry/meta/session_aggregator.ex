defmodule Mehungry.Meta.SessionAggregator do
  @moduledoc """
  Consent-independent, zero-PII session measurement.

  A connected LiveView process *is* a session: it is born on connected mount and
  dies on disconnect / navigation / tab close, so its lifetime is the session
  duration. The `MehungryWeb.SessionMetrics` `on_mount` hook calls `track/1` on
  every connected mount with no cookie-consent gate, so it measures 100% of
  connected traffic — the honest denominator Google Analytics can't give,
  because GA only counts the cookie-consented subset.

  This server monitors each tracked process and, when it dies, folds the elapsed
  time into a daily aggregate via `Mehungry.Meta.record_session/2`. The only
  state held — in memory, never persisted — is `monitor_ref => {start_utc,
  monotonic_start}`; a pid/ref is an ephemeral runtime handle, not personal
  data. Nothing identifying is stored anywhere.

  Granularity caveat: a `live_navigate` across pages starts a fresh LiveView
  process, so a multi-page visit fragments into several short sessions. Accepted
  for v1 (see the feature plan); a per-tab token is a future enhancement.
  """
  use GenServer

  require Logger

  alias Mehungry.Meta

  # Guards against a long-open tab (or a clock anomaly) recording an absurd
  # duration into the aggregate; sessions longer than this are capped.
  @max_duration_seconds 24 * 60 * 60

  @doc "Starts the aggregator (added to the `Mehungry.Application` supervision tree)."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Begins tracking `pid` (defaults to the caller — a connected LiveView process).
  Fire-and-forget: a cast, so a slow/missing aggregator never blocks mount.
  """
  def track(pid \\ self()) do
    GenServer.cast(__MODULE__, {:track, pid})
  end

  @impl true
  def init(:ok) do
    # ref => {start_utc :: DateTime.t(), monotonic_start :: integer()}
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:track, pid}, state) do
    ref = Process.monitor(pid)
    entry = {DateTime.utc_now(), System.monotonic_time(:second)}
    {:noreply, Map.put(state, ref, entry)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state, ref) do
      {nil, state} ->
        {:noreply, state}

      {{start_utc, monotonic_start}, state} ->
        duration =
          (System.monotonic_time(:second) - monotonic_start)
          |> max(0)
          |> min(@max_duration_seconds)

        record(start_utc, duration)
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp record(start_utc, duration) do
    # Test seam: the suite runs non-async LiveView tests in Ecto's `{:shared,
    # self()}` sandbox mode, so a tracked LiveView dying mid-suite would have
    # this global GenServer write a stray row into whichever *unrelated* test
    # currently owns the shared connection (flaky pollution). Default-off in
    # `config/test.exs`; the two tests that exercise the aggregator end-to-end
    # flip it back on for themselves.
    if Application.get_env(:mehungry, :session_metrics_recording, true) do
      Meta.record_session(start_utc, duration)
    else
      :ok
    end
  rescue
    error ->
      # Analytics must never take down the supervisor; log and drop.
      Logger.warning("[SessionAggregator] failed to record session: #{inspect(error)}")
  catch
    # A DB checkout can `exit` (not raise) — e.g. the pool/connection going away,
    # or the Ecto sandbox owner exiting in tests. Swallow it so the aggregator,
    # a permanent child, can't crash-loop the supervisor.
    kind, reason ->
      Logger.warning("[SessionAggregator] session record #{kind}: #{inspect(reason)}")
  end
end
