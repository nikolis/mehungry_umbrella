defmodule Mehungry.Telemetry.ErrorTracker do
  @moduledoc """
  DIY in-app error tracker. Attaches to Phoenix, LiveView and Oban exception
  telemetry, fingerprints each error and upserts it into `error_events`
  (incrementing `count` on repeat occurrences). Viewed via the LiveDashboard
  "Errors" page; pruned by `TelemetryPrunerWorker`.
  """

  use GenServer
  require Logger

  alias Mehungry.Telemetry.ErrorEvent

  @reason_limit 2_000
  @stacktrace_limit 8_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    attach_handlers()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:error_event, event}, state) do
    upsert(event)
    {:noreply, state}
  end

  # --- Telemetry handlers ---
  # Handlers must never raise: a raising handler gets detached by :telemetry.

  def handle_plug_exception(_event, _measurements, metadata, _config) do
    safe_cast(fn ->
      %{
        source: "plug",
        kind: metadata[:kind],
        reason: metadata[:reason],
        stacktrace: metadata[:stacktrace],
        context: %{route: metadata[:route]}
      }
    end)
  end

  def handle_live_view_exception([:phoenix, :live_view, stage, :exception], _msr, metadata, _cfg) do
    safe_cast(fn ->
      context =
        %{view: view_name(metadata), stage: to_string(stage)}
        |> maybe_put(:event, metadata[:event])

      %{
        source: "live_view",
        kind: metadata[:kind],
        reason: metadata[:reason],
        stacktrace: metadata[:stacktrace],
        context: context
      }
    end)
  end

  def handle_oban_exception(_event, _measurements, metadata, _config) do
    safe_cast(fn ->
      job = metadata[:job] || %{}

      %{
        source: "oban",
        kind: metadata[:kind],
        reason: metadata[:reason],
        stacktrace: metadata[:stacktrace],
        context: %{
          worker: Map.get(job, :worker),
          queue: Map.get(job, :queue),
          attempt: Map.get(job, :attempt)
        }
      }
    end)
  end

  # --- Private ---

  defp attach_handlers do
    handlers = [
      {"error-tracker-plug", [:phoenix, :router_dispatch, :exception],
       &__MODULE__.handle_plug_exception/4},
      {"error-tracker-lv-mount", [:phoenix, :live_view, :mount, :exception],
       &__MODULE__.handle_live_view_exception/4},
      {"error-tracker-lv-params", [:phoenix, :live_view, :handle_params, :exception],
       &__MODULE__.handle_live_view_exception/4},
      {"error-tracker-lv-event", [:phoenix, :live_view, :handle_event, :exception],
       &__MODULE__.handle_live_view_exception/4},
      {"error-tracker-oban", [:oban, :job, :exception], &__MODULE__.handle_oban_exception/4}
    ]

    for {id, event, handler} <- handlers do
      case :telemetry.attach(id, event, handler, %{}) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end
  end

  defp safe_cast(build_fun) do
    GenServer.cast(__MODULE__, {:error_event, build_fun.()})
  rescue
    _ -> :ok
  end

  defp upsert(event) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    kind = to_string(event[:kind] || "error")
    reason = format_reason(event[:kind], event[:reason])
    stacktrace = format_stacktrace(event[:stacktrace])
    context = compact(event[:context] || %{})
    fingerprint = fingerprint(event, kind)

    row = %{
      fingerprint: fingerprint,
      kind: kind,
      source: event.source,
      reason: reason,
      stacktrace: stacktrace,
      context: context,
      count: 1,
      first_seen: now,
      last_seen: now
    }

    Mehungry.Repo.insert_all(ErrorEvent, [row],
      on_conflict: [
        inc: [count: 1],
        set: [last_seen: now, reason: reason, stacktrace: stacktrace, context: context]
      ],
      conflict_target: :fingerprint
    )
  rescue
    e -> Logger.error("[ErrorTracker] Upsert failed: #{inspect(e)}")
  end

  # Fingerprint on the stable parts of an error: where it came from, its kind,
  # its type (module for exception structs) and the first app-owned stack frame.
  # Deliberately excludes the message text, which often embeds ids/params.
  defp fingerprint(event, kind) do
    type =
      case event[:reason] do
        %struct{} -> inspect(struct)
        other -> other |> inspect(limit: 5) |> String.slice(0, 100)
      end

    payload =
      Enum.join([event.source, kind, type, app_frame(event[:stacktrace])], "|")

    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower) |> String.slice(0, 32)
  end

  defp app_frame(stacktrace) when is_list(stacktrace) do
    Enum.find_value(stacktrace, "", fn
      {module, fun, arity, _location} ->
        if module |> to_string() |> String.starts_with?("Elixir.Mehungry") do
          "#{inspect(module)}.#{fun}/#{arity}"
        end

      _ ->
        nil
    end)
  end

  defp app_frame(_), do: ""

  defp format_reason(kind, reason) do
    Exception.format_banner(kind || :error, reason)
    |> String.slice(0, @reason_limit)
  rescue
    _ -> reason |> inspect() |> String.slice(0, @reason_limit)
  end

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    Exception.format_stacktrace(stacktrace) |> String.slice(0, @stacktrace_limit)
  rescue
    _ -> ""
  end

  defp format_stacktrace(_), do: ""

  defp view_name(%{socket: %{view: view}}) when is_atom(view), do: inspect(view)
  defp view_name(_metadata), do: "unknown"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))

  defp compact(context) do
    context
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {k, to_string(v)} end)
  end
end
