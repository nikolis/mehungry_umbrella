defmodule Mehungry.Telemetry.ActionContext do
  @moduledoc """
  Tags the current process with a label + unique id describing the
  HTTP request / LiveView callback / Oban job it is currently executing,
  by attaching to the `:start`/`:stop`/`:exception` telemetry spans Phoenix,
  LiveView and Oban already emit.

  Ecto's `[:mehungry, :repo, :query]` telemetry fires synchronously in the
  same process that issued the query, so `MetricsBuffer` can read this
  context (via `current/0`) at query time to tag each raw sample with the
  action that triggered it. Not propagated across spawned Tasks — queries
  fired from a `Task.async` inside a callback show up unlabeled.
  """

  @context_key :mehungry_query_action

  def attach do
    handlers = [
      {"action-context-http", [:phoenix, :router_dispatch, :start], &__MODULE__.handle_start/4},
      {"action-context-http-stop", [:phoenix, :router_dispatch, :stop],
       &__MODULE__.handle_stop/4},
      {"action-context-http-exception", [:phoenix, :router_dispatch, :exception],
       &__MODULE__.handle_stop/4},
      {"action-context-lv-mount", [:phoenix, :live_view, :mount, :start],
       &__MODULE__.handle_start/4},
      {"action-context-lv-mount-stop", [:phoenix, :live_view, :mount, :stop],
       &__MODULE__.handle_stop/4},
      {"action-context-lv-mount-exception", [:phoenix, :live_view, :mount, :exception],
       &__MODULE__.handle_stop/4},
      {"action-context-lv-params", [:phoenix, :live_view, :handle_params, :start],
       &__MODULE__.handle_start/4},
      {"action-context-lv-params-stop", [:phoenix, :live_view, :handle_params, :stop],
       &__MODULE__.handle_stop/4},
      {"action-context-lv-params-exception", [:phoenix, :live_view, :handle_params, :exception],
       &__MODULE__.handle_stop/4},
      {"action-context-lv-event", [:phoenix, :live_view, :handle_event, :start],
       &__MODULE__.handle_start/4},
      {"action-context-lv-event-stop", [:phoenix, :live_view, :handle_event, :stop],
       &__MODULE__.handle_stop/4},
      {"action-context-lv-event-exception", [:phoenix, :live_view, :handle_event, :exception],
       &__MODULE__.handle_stop/4},
      {"action-context-oban-start", [:oban, :job, :start], &__MODULE__.handle_start/4},
      {"action-context-oban-stop", [:oban, :job, :stop], &__MODULE__.handle_stop/4},
      {"action-context-oban-exception", [:oban, :job, :exception], &__MODULE__.handle_stop/4}
    ]

    for {id, event, handler} <- handlers do
      case :telemetry.attach(id, event, handler, %{}) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end
  end

  @doc "Reads the currently active `{label, action_id}`, or a background placeholder."
  def current do
    Process.get(@context_key, {"background", nil})
  end

  def handle_start(event, _measurements, metadata, _config) do
    Process.put(
      @context_key,
      {label(event, metadata), System.unique_integer([:positive, :monotonic])}
    )
  rescue
    _ -> :ok
  end

  def handle_stop(_event, _measurements, _metadata, _config) do
    Process.delete(@context_key)
    :ok
  end

  # --- Label building ---

  defp label([:phoenix, :router_dispatch, :start], %{conn: conn, route: route}) do
    "HTTP #{conn.method} #{route}"
  end

  defp label([:phoenix, :router_dispatch, :start], _metadata), do: "HTTP request"

  defp label([:phoenix, :live_view, :mount, :start], metadata) do
    "#{view_name(metadata)}#mount"
  end

  defp label([:phoenix, :live_view, :handle_params, :start], metadata) do
    "#{view_name(metadata)}#handle_params"
  end

  defp label([:phoenix, :live_view, :handle_event, :start], metadata) do
    "#{view_name(metadata)}##{metadata[:event] || "unknown"}"
  end

  defp label([:oban, :job, :start], metadata) do
    "Oban #{worker_name(metadata[:worker])}"
  end

  defp label(_event, _metadata), do: "background"

  defp view_name(%{socket: %{view: view}}) when is_atom(view) do
    view |> Module.split() |> List.last()
  end

  defp view_name(_metadata), do: "unknown"

  defp worker_name(w) when is_atom(w), do: w |> Module.split() |> List.last()
  defp worker_name(w), do: to_string(w)
end
