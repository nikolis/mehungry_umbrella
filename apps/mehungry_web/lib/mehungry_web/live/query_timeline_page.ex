defmodule MehungryWeb.QueryTimelinePage do
  use Phoenix.LiveDashboard.PageBuilder

  @ranges [{"5m", 5}, {"15m", 15}, {"30m", 30}, {"60m", 60}]

  @impl true
  def menu_link(_, _), do: {:ok, "Query Timeline"}

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       range: "15m",
       ranges: @ranges,
       groups: fetch_groups("15m"),
       expanded: nil,
       expanded_groups: MapSet.new()
     )}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, assign(socket, groups: fetch_groups(socket.assigns.range))}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, range: range, groups: fetch_groups(range))}
  end

  @impl true
  def handle_event("toggle", %{"key" => key}, socket) do
    expanded = if socket.assigns.expanded == key, do: nil, else: key
    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def handle_event("toggle_group", %{"key" => key}, socket) do
    expanded_groups =
      if MapSet.member?(socket.assigns.expanded_groups, key) do
        MapSet.delete(socket.assigns.expanded_groups, key)
      else
        MapSet.put(socket.assigns.expanded_groups, key)
      end

    {:noreply, assign(socket, expanded_groups: expanded_groups)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="padding: 1rem;">
      <div style="margin-bottom: 1.25rem; display: flex; align-items: center; gap: 0.5rem;">
        <span style="font-weight: 600; margin-right: 0.5rem;">Time range:</span>
        <%= for {label, _mins} <- @ranges do %>
          <button
            phx-click="set_range"
            phx-value-range={label}
            style={range_button_style(@range == label)}
          >
            {label}
          </button>
        <% end %>
        <span style="margin-left: auto; color: #6b7280; font-size: 0.85rem;">
          {length(@groups)} actions · raw executions, in-memory only ·
          grouped by the mount/event/request/job that fired them · retained 60 min
        </span>
      </div>

      <%= if @groups == [] do %>
        <p style="color: #6b7280; font-style: italic;">
          No queries recorded yet in this window.
        </p>
      <% else %>
        <%= for group <- @groups do %>
          <% group_key = to_string(group.key) %>
          <% is_open = MapSet.member?(@expanded_groups, group_key) %>
          <div style="margin-bottom: 1rem; border: 1px solid #e5e7eb; border-radius: 6px; overflow: hidden;">
            <div
              phx-click="toggle_group"
              phx-value-key={group_key}
              style="padding: 0.5rem 0.75rem; background: #f3f4f6; font-weight: 600; display: flex; justify-content: space-between; cursor: pointer; user-select: none;"
            >
              <span>{if is_open, do: "▾", else: "▸"} {group.action}</span>
              <span style="color: #6b7280; font-weight: 400; font-size: 0.85rem;">
                {length(group.events)} quer{if length(group.events) == 1, do: "y", else: "ies"} · {fmt(
                  group.total_ms
                )}ms total · latest {fmt_time(group.latest)}
              </span>
            </div>
            <%= if is_open do %>
              <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem;">
                <thead>
                  <tr style="border-bottom: 1px solid #e5e7eb; text-align: left;">
                    <th style={th_style()}>Time</th>
                    <th style={th_style()}>Source</th>
                    <th style={th_style()}>Query</th>
                    <th style={th_style(:right)}>Duration (ms)</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {event, idx} <- Enum.with_index(group.events) do %>
                    <% key = "#{group_key}-#{idx}" %>
                    <tr phx-click="toggle" phx-value-key={key} style="cursor: pointer;">
                      <td style={td_style()}><code>{fmt_time(event.time)}</code></td>
                      <td style={td_style()}><code>{event.source}</code></td>
                      <td style={td_style()}><code>{truncate(event.query, 90)}</code></td>
                      <td style={td_style(:right)}>{fmt(event.duration_ms)}</td>
                    </tr>
                    <%= if @expanded == key do %>
                      <tr>
                        <td
                          colspan="4"
                          style="padding: 0.75rem; background: #f9fafb; border-bottom: 1px solid #e5e7eb;"
                        >
                          <strong>Full query:</strong>
                          <pre style={pre_style()}><%= event.query %></pre>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # --- Data fetching ---

  defp fetch_groups(range) do
    minutes = range_to_minutes(range)

    Mehungry.Telemetry.MetricsBuffer.list_recent_query_events(minutes)
    |> Enum.group_by(& &1.action_id)
    |> Enum.map(fn {action_id, events} ->
      sorted = Enum.sort_by(events, & &1.time, {:asc, DateTime})

      %{
        key: action_id || "background",
        action: List.first(sorted).action,
        events: sorted,
        latest: List.last(sorted).time,
        total_ms: Enum.sum(Enum.map(sorted, & &1.duration_ms))
      }
    end)
    |> Enum.sort_by(& &1.latest, {:desc, DateTime})
  rescue
    _ -> []
  end

  defp range_to_minutes(range) do
    @ranges
    |> Enum.find({nil, 15}, fn {label, _} -> label == range end)
    |> elem(1)
  end

  # --- Formatting helpers ---

  defp truncate(nil, _), do: "—"

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp fmt(nil), do: "—"
  defp fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp fmt(v), do: to_string(v)

  defp fmt_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S.%f") |> String.slice(0, 12)
  defp fmt_time(_), do: "—"

  # --- Style helpers ---

  defp range_button_style(active) do
    base =
      "padding: 0.25rem 0.75rem; border-radius: 4px; border: 1px solid #d1d5db; cursor: pointer; font-size: 0.85rem;"

    if active do
      base <> " background: #3b82f6; color: white; border-color: #3b82f6; font-weight: 600;"
    else
      base <> " background: white; color: #374151;"
    end
  end

  defp th_style(align \\ :left) do
    "padding: 0.5rem 0.75rem; font-weight: 600; color: #374151; text-align: #{align};"
  end

  defp td_style(align \\ :left) do
    "padding: 0.4rem 0.75rem; text-align: #{align}; border-bottom: 1px solid #f3f4f6;"
  end

  defp pre_style do
    "background: #111827; color: #f9fafb; padding: 0.75rem; border-radius: 4px; " <>
      "font-size: 0.8rem; overflow-x: auto; white-space: pre-wrap; margin: 0.25rem 0 0 0;"
  end
end
