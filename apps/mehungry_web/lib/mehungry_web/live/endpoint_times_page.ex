defmodule MehungryWeb.EndpointTimesPage do
  @moduledoc """
  Custom LiveDashboard page ("Endpoints" menu item) listing HTTP routes,
  LiveView mounts, and LiveView events by worst observed latency.

  Reads `Mehungry.Telemetry.Snapshot` rows (5-minute aggregates written by
  `Mehungry.Telemetry.MetricsBuffer`) for the three endpoint-shaped metrics
  in `@endpoint_metrics`, restricted to the selected time range (one of
  `@ranges`: 1h/6h/24h/7d). Because a single endpoint can appear in several
  5-minute windows within the range, each `{metric, tags}` pair is collapsed
  to its single worst (highest p95) window before the table is sorted worst
  first — this page answers "what's the worst this endpoint has looked
  recently", not "what does it look like right now" (see
  `docs/observability.md` for the full dashboard tour).
  """

  use Phoenix.LiveDashboard.PageBuilder
  import Ecto.Query

  @ranges [{"1h", 3_600}, {"6h", 21_600}, {"24h", 86_400}, {"7d", 604_800}]
  @endpoint_metrics [
    "phoenix.request.duration",
    "live_view.mount.duration",
    "live_view.handle_event.duration"
  ]

  @impl true
  def menu_link(_, _), do: {:ok, "Endpoints"}

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       range: "24h",
       ranges: @ranges,
       endpoints: fetch_endpoints("24h")
     )}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, assign(socket, endpoints: fetch_endpoints(socket.assigns.range))}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, range: range, endpoints: fetch_endpoints(range))}
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
          {length(@endpoints)} distinct endpoints · grouped by route/view (+event) ·
          worst p95 first · flushed every 5 min · retained 30 days
        </span>
      </div>

      <%= if @endpoints == [] do %>
        <p style="color: #6b7280; font-style: italic;">
          No data yet — the first snapshot is written 5 minutes after server start.
        </p>
      <% else %>
        <div style="overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem;">
            <thead>
              <tr style="border-bottom: 2px solid #e5e7eb; text-align: left;">
                <th style={th_style()}>Type</th>
                <th style={th_style()}>Endpoint</th>
                <th style={th_style(:right)}>Avg (ms)</th>
                <th style={th_style(:right)}>Min (ms)</th>
                <th style={th_style(:right)}>Max (ms)</th>
                <th style={th_style(:right)}>p95 (ms)</th>
                <th style={th_style(:right)}># Samples</th>
              </tr>
            </thead>
            <tbody>
              <%= for {ep, idx} <- Enum.with_index(@endpoints) do %>
                <tr style={row_style(idx)}>
                  <td style={td_style()}><code>{type_label(ep.metric)}</code></td>
                  <td style={td_style()}><code>{endpoint_label(ep.metric, ep.tags)}</code></td>
                  <td style={td_style(:right)}>{fmt(ep.avg)}</td>
                  <td style={td_style(:right)}>{fmt(ep.min)}</td>
                  <td style={td_style(:right)}>{fmt(ep.max)}</td>
                  <td style={td_style(:right)}>{fmt(ep.p95)}</td>
                  <td style={td_style(:right)}>{ep.sample_count}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Data fetching ---

  # Loads the endpoint table for `range` (one of the `@ranges` labels):
  # fetches up to 2000 `Snapshot` rows for the endpoint metrics within the
  # range, collapses each `{metric, tags}` pair to its single worst (highest
  # p95) window, and sorts worst-first. Returns `[]` on any query error
  # rather than crashing the dashboard page.
  defp fetch_endpoints(range) do
    seconds = range_to_seconds(range)
    cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)

    Mehungry.Repo.all(
      from(s in Mehungry.Telemetry.Snapshot,
        where: s.period_start >= ^cutoff and s.metric in ^@endpoint_metrics,
        order_by: [desc: s.p95],
        limit: 2000
      )
    )
    |> Enum.group_by(&{&1.metric, &1.tags})
    |> Enum.map(fn {_key, rows} -> Enum.max_by(rows, & &1.p95) end)
    |> Enum.sort_by(& &1.p95, :desc)
  rescue
    _ -> []
  end

  @doc """
  Resolves a range button label to its width in seconds, defaulting to 24h
  (86400s) for a label not found in `@ranges`.

  ## Examples

      iex> MehungryWeb.EndpointTimesPage.range_to_seconds("1h")
      3_600

      iex> MehungryWeb.EndpointTimesPage.range_to_seconds("7d")
      604_800

      iex> MehungryWeb.EndpointTimesPage.range_to_seconds("nonsense")
      86_400

  """
  def range_to_seconds(range) do
    @ranges
    |> Enum.find({nil, 86_400}, fn {label, _} -> label == range end)
    |> elem(1)
  end

  # --- Formatting helpers ---

  @doc """
  Human label for the "Type" column, keyed off the raw metric name. Unknown
  metrics fall back to the metric name itself.

  ## Examples

      iex> MehungryWeb.EndpointTimesPage.type_label("phoenix.request.duration")
      "HTTP"

      iex> MehungryWeb.EndpointTimesPage.type_label("live_view.mount.duration")
      "LV mount"

      iex> MehungryWeb.EndpointTimesPage.type_label("live_view.handle_event.duration")
      "LV event"

      iex> MehungryWeb.EndpointTimesPage.type_label("something.else")
      "something.else"

  """
  def type_label("phoenix.request.duration"), do: "HTTP"
  def type_label("live_view.mount.duration"), do: "LV mount"
  def type_label("live_view.handle_event.duration"), do: "LV event"
  def type_label(other), do: other

  @doc """
  Human label for the "Endpoint" column. Which tag identifies the endpoint
  differs per metric: `route` for HTTP requests, `view` for LiveView mounts,
  and `view` + `event` for LiveView events. Falls back to `"unknown"` when
  the expected tag is missing.

  ## Examples

      iex> MehungryWeb.EndpointTimesPage.endpoint_label("phoenix.request.duration", %{"route" => "/recipes/:id"})
      "/recipes/:id"

      iex> MehungryWeb.EndpointTimesPage.endpoint_label("live_view.mount.duration", %{"view" => "RecipeLive"})
      "RecipeLive"

      iex> MehungryWeb.EndpointTimesPage.endpoint_label("live_view.handle_event.duration", %{"view" => "RecipeLive", "event" => "save"})
      "RecipeLive #save"

      iex> MehungryWeb.EndpointTimesPage.endpoint_label("phoenix.request.duration", %{})
      "unknown"

  """
  def endpoint_label("phoenix.request.duration", tags), do: Map.get(tags, "route", "unknown")
  def endpoint_label("live_view.mount.duration", tags), do: Map.get(tags, "view", "unknown")

  def endpoint_label("live_view.handle_event.duration", tags) do
    "#{Map.get(tags, "view", "unknown")} ##{Map.get(tags, "event", "unknown")}"
  end

  def endpoint_label(_metric, tags), do: inspect(tags)

  @doc """
  Formats a metric value for table display. `nil` (no samples in the
  selected window for that column) renders as an em dash; everything else is
  fixed to two decimal places.

  ## Examples

      iex> MehungryWeb.EndpointTimesPage.fmt(nil)
      "—"

      iex> MehungryWeb.EndpointTimesPage.fmt(12.3)
      "12.30"

      iex> MehungryWeb.EndpointTimesPage.fmt(12.3456)
      "12.35"

  """
  def fmt(nil), do: "—"
  def fmt(v), do: :erlang.float_to_binary(v, decimals: 2)

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

  defp row_style(idx) do
    if rem(idx, 2) == 0, do: "background: white;", else: "background: #f9fafb;"
  end
end
