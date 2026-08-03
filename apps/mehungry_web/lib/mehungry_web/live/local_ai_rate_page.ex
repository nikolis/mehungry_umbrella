defmodule MehungryWeb.LocalAiRatePage do
  @moduledoc """
  Custom LiveDashboard page ("LocalAI Rate") showing requests/min for the
  token-guarded LocalAi REST API (`/api/local_ai/*`), per route and overall.

  Backed entirely by `Mehungry.Telemetry.RequestRate.local_ai/1`: the table is
  the 5-minute `Snapshot` history over the selected range, and the banner above
  it is the live count from the in-memory buffer since the last flush. See
  `docs/observability.md`.
  """

  use Phoenix.LiveDashboard.PageBuilder

  @ranges [{"1h", 3_600}, {"6h", 21_600}, {"24h", 86_400}, {"7d", 604_800}]

  @impl true
  def menu_link(_, _), do: {:ok, "LocalAI Rate"}

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, range: "1h", ranges: @ranges, data: fetch("1h"))}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, assign(socket, data: fetch(socket.assigns.range))}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, range: range, data: fetch(range))}
  end

  defp fetch(range) do
    Mehungry.Telemetry.RequestRate.local_ai(range_to_seconds(range))
  end

  @doc """
  Resolves a range button label to its width in seconds, defaulting to 1h
  (3600s) for an unknown label.

  ## Examples

      iex> MehungryWeb.LocalAiRatePage.range_to_seconds("6h")
      21_600

      iex> MehungryWeb.LocalAiRatePage.range_to_seconds("nonsense")
      3_600

  """
  def range_to_seconds(range) do
    @ranges
    |> Enum.find({nil, 3_600}, fn {label, _} -> label == range end)
    |> elem(1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="padding: 1rem;">
      <div style="margin-bottom: 1.25rem; display: flex; align-items: center; gap: 0.5rem;">
        <span style="font-weight: 600; margin-right: 0.5rem;">Time range:</span>
        <%= for {label, _secs} <- @ranges do %>
          <button
            phx-click="set_range"
            phx-value-range={label}
            style={range_button_style(@range == label)}
          >
            {label}
          </button>
        <% end %>
        <span style="margin-left: auto; color: #6b7280; font-size: 0.85rem;">
          {@data.route_prefix}/* · window average from 5-min snapshots · flushed every 5 min
        </span>
      </div>

      <div style="display: flex; gap: 1rem; margin-bottom: 1.25rem; flex-wrap: wrap;">
        <div style={stat_style()}>
          <div style={stat_label_style()}>Total (window avg)</div>
          <div style={stat_value_style()}>{fmt(@data.total.per_min)} <small>req/min</small></div>
          <div style={stat_sub_style()}>{@data.total.requests} requests</div>
        </div>
        <div style={stat_style()}>
          <div style={stat_label_style()}>Live (since last flush)</div>
          <div style={stat_value_style()}>{fmt(@data.live.per_min)} <small>req/min</small></div>
          <div style={stat_sub_style()}>
            {@data.live.requests} requests in last {live_seconds(@data.live)}s
          </div>
        </div>
      </div>

      <%= if @data.routes == [] do %>
        <p style="color: #6b7280; font-style: italic;">
          No LocalAI requests recorded in this range — the first snapshot is written
          5 minutes after the first request.
        </p>
      <% else %>
        <div style="overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem;">
            <thead>
              <tr style="border-bottom: 2px solid #e5e7eb; text-align: left;">
                <th style={th_style()}>Route</th>
                <th style={th_style(:right)}>req/min (avg)</th>
                <th style={th_style(:right)}>req/min (latest 5m)</th>
                <th style={th_style(:right)}>Requests</th>
                <th style={th_style(:right)}>Avg (ms)</th>
              </tr>
            </thead>
            <tbody>
              <%= for {route, idx} <- Enum.with_index(@data.routes) do %>
                <tr style={row_style(idx)}>
                  <td style={td_style()}><code>{route.route}</code></td>
                  <td style={td_style(:right)}>{fmt(route.per_min)}</td>
                  <td style={td_style(:right)}>{fmt(route.latest_5m_per_min)}</td>
                  <td style={td_style(:right)}>{route.requests}</td>
                  <td style={td_style(:right)}>{fmt(route.avg_ms)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp live_seconds(%{since_last_flush_seconds: nil}), do: "?"
  defp live_seconds(%{since_last_flush_seconds: s}), do: s

  @doc """
  Formats a numeric metric for display: `nil` renders as an em dash, everything
  else keeps up to two decimals.

  ## Examples

      iex> MehungryWeb.LocalAiRatePage.fmt(nil)
      "—"

      iex> MehungryWeb.LocalAiRatePage.fmt(2.0)
      "2.0"

  """
  def fmt(nil), do: "—"
  def fmt(v) when is_float(v), do: to_string(v)
  def fmt(v), do: to_string(v)

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

  defp stat_style do
    "flex: 1; min-width: 180px; padding: 1rem; border: 1px solid #e5e7eb; border-radius: 8px; background: #f9fafb;"
  end

  defp stat_label_style, do: "color: #6b7280; font-size: 0.8rem; text-transform: uppercase;"

  defp stat_value_style,
    do: "font-size: 1.6rem; font-weight: 700; color: #111827; margin: 0.25rem 0;"

  defp stat_sub_style, do: "color: #6b7280; font-size: 0.85rem;"

  defp th_style(align \\ :left) do
    "padding: 0.5rem 0.75rem; font-weight: 600; color: #374151; text-align: #{align};"
  end

  defp td_style(align \\ :left) do
    "padding: 0.4rem 0.75rem; text-align: #{align}; border-bottom: 1px solid #f3f4f6;"
  end

  defp row_style(idx) do
    if rem(idx, 2) == 0, do: "background: white;", else: "background: #f9fafb;"
  end
end
