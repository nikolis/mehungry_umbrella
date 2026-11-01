defmodule Mehungry.Meta.SessionAggregator do
  @moduledoc """
  Consent-independent, zero-PII measurement of **real human visits**.

  A browser tab mints a per-tab `visit_token` (in `sessionStorage`) and sends it
  as a LiveSocket connect param; the `MehungryWeb.SessionMetrics` `on_mount` hook
  calls `track/3` with it on every connected mount, with no cookie-consent gate,
  so this measures 100% of connected traffic — the honest denominator Google
  Analytics can't give, because GA only counts the cookie-consented subset.

  Unlike a naive "one LiveView process = one session" model, this aggregates by
  **token**, so a multi-page visit (each `live_navigate` spawns a fresh process),
  a socket reconnect, and duplicate mounts all fold into a single visit instead of
  inflating the count. When a visit goes idle (no live processes for
  `@visit_idle_timeout`) it is finalized by a periodic sweep and folded into the
  daily aggregate via `Mehungry.Meta.record_session/2` — but **only if it
  qualifies as a real visit**, mirroring GA4's engaged-session definition:

      engaged? OR duration >= 10s OR views >= 2

  Single-shot instant loads, idle auto-loads, and JS-executing bots that never
  interact are therefore dropped. Known-bot User-Agents are dropped at `track`
  time before any state is created.

  The only state held — in memory, never persisted — is per-token visit timing
  (`start_utc`, monotonic marks, a `views` count, an `engaged?` flag, and the set
  of live monitor refs) plus `ref => token` / `pid => token` lookup maps. A
  token, pid, or ref is an ephemeral runtime handle, not personal data; the User
  Agent is read only to decide whether to count and is never stored. Nothing
  identifying is persisted anywhere (see `Mehungry.Meta.DailySessionMetric`).

  Duration caveat: without a visibility heartbeat, a visit's duration is its
  wall-clock span from first mount to last process death (capped at
  `@max_duration_seconds`), not active engaged time. Accepted for this iteration.
  """
  use GenServer

  require Logger

  alias Mehungry.Meta

  # A visit counts as "real" if it was engaged, lasted at least this long, or had
  # at least two views (GA4-parity engaged-session definition).
  @engaged_min_seconds 10

  # A visit with no live processes for this long is considered finished and
  # finalized. Matches GA4's 30-minute session timeout so a tab that drops its
  # socket and reconnects (mobile backgrounding, network blip) stays one visit.
  @visit_idle_timeout 30 * 60

  # How often the sweep runs to finalize idle visits.
  @sweep_interval_ms 60_000

  # Guards against a long-open tab (or a clock anomaly) recording an absurd
  # duration into the aggregate; visits longer than this are capped.
  @max_duration_seconds 24 * 60 * 60

  # Substrings that identify non-human User-Agents. Matched case-insensitively at
  # track time; such a visit is never tracked. (HTTP-only crawlers like
  # facebookexternalhit never open the LiveView socket, but listing them is
  # harmless; the real catch here is JS-executing headless/monitor bots.)
  @bot_ua_regex ~r/bot|crawl|spider|slurp|headless|lighthouse|monitor|pingdom|uptimerobot|phantom|puppeteer|playwright|preview|python-requests|curl|wget|go-http|axios|facebookexternalhit|facebot/i

  @doc "Starts the aggregator (added to the `Mehungry.Application` supervision tree)."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Begins tracking a connected LiveView `pid` (defaults to the caller) as part of
  the visit identified by `token`. `user_agent` is used only to drop known bots.

  A `nil` token (old cached client / non-JS) falls back to a unique per-process
  token, degrading gracefully to the old per-process grain while still gated.

  Fire-and-forget: a cast, so a slow/missing aggregator never blocks mount.
  """
  def track(token, user_agent \\ nil, pid \\ self()) do
    GenServer.cast(__MODULE__, {:track, token, user_agent, pid})
  end

  @doc """
  Marks the visit owning `pid` (defaults to the caller) as engaged — a genuine
  user interaction happened — so it qualifies as a real visit regardless of
  duration or view count.
  """
  def engaged(pid \\ self()) do
    GenServer.cast(__MODULE__, {:engaged, pid})
  end

  @doc """
  Finalizes every visit that currently has no live processes, ignoring the idle
  timeout. Synchronous — primarily a test seam for deterministic assertions.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush)
  end

  @impl true
  def init(:ok) do
    schedule_sweep()
    {:ok, %{visits: %{}, refs: %{}, pids: %{}}}
  end

  @impl true
  def handle_cast({:track, token, user_agent, pid}, state) do
    if bot?(user_agent) do
      {:noreply, state}
    else
      {:noreply, do_track(state, token || synthetic_token(pid), pid)}
    end
  end

  @impl true
  def handle_cast({:engaged, pid}, state) do
    case Map.get(state.pids, pid) do
      nil ->
        {:noreply, state}

      token ->
        {:noreply, update_visit(state, token, fn v -> %{v | engaged?: true, last_mono: now_mono()} end)}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, finalize_idle(state, _force? = true)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {token, refs} ->
        state = %{state | refs: refs, pids: Map.delete(state.pids, pid)}

        state =
          update_visit(state, token, fn v ->
            %{v | live_refs: MapSet.delete(v.live_refs, ref), last_mono: now_mono()}
          end)

        {:noreply, state}
    end
  end

  def handle_info(:sweep, state) do
    schedule_sweep()
    {:noreply, finalize_idle(state, _force? = false)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---- tracking ----

  defp do_track(state, token, pid) do
    ref = Process.monitor(pid)

    visits =
      Map.update(
        state.visits,
        token,
        new_visit(ref),
        fn v ->
          %{v | views: v.views + 1, last_mono: now_mono(), live_refs: MapSet.put(v.live_refs, ref)}
        end
      )

    %{
      state
      | visits: visits,
        refs: Map.put(state.refs, ref, token),
        pids: Map.put(state.pids, pid, token)
    }
  end

  defp new_visit(ref) do
    mono = now_mono()

    %{
      start_utc: DateTime.utc_now(),
      start_mono: mono,
      last_mono: mono,
      engaged?: false,
      views: 1,
      live_refs: MapSet.new([ref])
    }
  end

  defp update_visit(state, token, fun) do
    case Map.get(state.visits, token) do
      nil -> state
      visit -> %{state | visits: Map.put(state.visits, token, fun.(visit))}
    end
  end

  # ---- finalization ----

  # Finalize visits with no live processes. When `force?` (flush) ignore the idle
  # timeout; otherwise require the visit to have been idle for `@visit_idle_timeout`.
  defp finalize_idle(state, force?) do
    now = now_mono()

    {done, remaining} =
      Enum.split_with(state.visits, fn {_token, v} ->
        MapSet.size(v.live_refs) == 0 and
          (force? or now - v.last_mono >= @visit_idle_timeout)
      end)

    Enum.each(done, fn {_token, v} -> finalize(v) end)
    %{state | visits: Map.new(remaining)}
  end

  defp finalize(visit) do
    duration =
      (visit.last_mono - visit.start_mono)
      |> max(0)
      |> min(@max_duration_seconds)

    real? = visit.engaged? or duration >= @engaged_min_seconds or visit.views >= 2

    if real?, do: record(visit.start_utc, duration)
    :ok
  end

  defp record(start_utc, duration) do
    # Test seam: the suite runs non-async LiveView tests in Ecto's `{:shared,
    # self()}` sandbox mode, so finalizing a visit mid-suite would have this
    # global GenServer write a stray row into whichever *unrelated* test
    # currently owns the shared connection (flaky pollution). Default-off in
    # `config/test.exs`; the tests that exercise the aggregator end-to-end flip
    # it back on for themselves.
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

  # ---- helpers ----

  defp bot?(nil), do: false
  defp bot?(ua) when is_binary(ua), do: Regex.match?(@bot_ua_regex, ua)
  defp bot?(_), do: false

  defp synthetic_token(pid), do: "pid:" <> inspect(pid)

  defp now_mono, do: System.monotonic_time(:second)

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
