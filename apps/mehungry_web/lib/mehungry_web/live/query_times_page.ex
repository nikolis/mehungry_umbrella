defmodule MehungryWeb.QueryTimesPage do
  use Phoenix.LiveDashboard.PageBuilder
  import Ecto.Query

  @ranges [{"1h", 3_600}, {"6h", 21_600}, {"24h", 86_400}, {"7d", 604_800}]

  @impl true
  def menu_link(_, _), do: {:ok, "Queries"}

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       range: "24h",
       ranges: @ranges,
       profiles: fetch_profiles("24h"),
       expanded: nil
     )}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, assign(socket, profiles: fetch_profiles(socket.assigns.range))}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign(socket, range: range, profiles: fetch_profiles(range))}
  end

  @impl true
  def handle_event("toggle", %{"fingerprint" => fp}, socket) do
    expanded = if socket.assigns.expanded == fp, do: nil, else: fp
    {:noreply, assign(socket, expanded: expanded)}
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
          {length(@profiles)} distinct queries · grouped by fingerprint (source + SQL shape) ·
          worst p95 first · flushed every 5 min · retained 30 days · click a row for the full statement
        </span>
      </div>

      <%= if @profiles == [] do %>
        <p style="color: #6b7280; font-style: italic;">
          No data yet — the first snapshot is written 5 minutes after server start.
        </p>
      <% else %>
        <div style="overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem;">
            <thead>
              <tr style="border-bottom: 2px solid #e5e7eb; text-align: left;">
                <th style={th_style()}>Source</th>
                <th style={th_style()}>Query</th>
                <th style={th_style(:right)}>Avg (ms)</th>
                <th style={th_style(:right)}>Min (ms)</th>
                <th style={th_style(:right)}>Max (ms)</th>
                <th style={th_style(:right)}>p95 (ms)</th>
                <th style={th_style(:right)}># Samples</th>
              </tr>
            </thead>
            <tbody>
              <%= for profile <- @profiles do %>
                <tr
                  phx-click="toggle"
                  phx-value-fingerprint={profile.fingerprint}
                  style={row_style(@expanded == profile.fingerprint)}
                >
                  <td style={td_style()}><code>{profile.source}</code></td>
                  <td style={td_style()}><code>{truncate(profile.query, 90)}</code></td>
                  <td style={td_style(:right)}>{fmt(profile.avg)}</td>
                  <td style={td_style(:right)}>{fmt(profile.min)}</td>
                  <td style={td_style(:right)}>{fmt(profile.max)}</td>
                  <td style={td_style(:right)}>{fmt(profile.p95)}</td>
                  <td style={td_style(:right)}>{profile.sample_count}</td>
                </tr>
                <%= if @expanded == profile.fingerprint do %>
                  <tr>
                    <td
                      colspan="7"
                      style="padding: 0.75rem; background: #f9fafb; border-bottom: 1px solid #e5e7eb;"
                    >
                      <strong>Full query:</strong>
                      <pre style={pre_style()}><%= profile.query %></pre>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Data fetching ---

  # One row per fingerprint per window; a query can appear in several windows
  # within the range, so keep only its worst (highest p95) window for the list.
  defp fetch_profiles(range) do
    seconds = range_to_seconds(range)
    cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)

    Mehungry.Repo.all(
      from(p in Mehungry.Telemetry.QueryProfile,
        where: p.period_start >= ^cutoff,
        order_by: [desc: p.p95],
        limit: 2000
      )
    )
    |> Enum.group_by(& &1.fingerprint)
    |> Enum.map(fn {_fp, rows} -> Enum.max_by(rows, & &1.p95) end)
    |> Enum.sort_by(& &1.p95, :desc)
  rescue
    _ -> []
  end

  defp range_to_seconds(range) do
    @ranges
    |> Enum.find({nil, 86_400}, fn {label, _} -> label == range end)
    |> elem(1)
  end

  # --- Formatting helpers ---

  defp truncate(nil, _), do: "—"

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp fmt(nil), do: "—"
  defp fmt(v), do: :erlang.float_to_binary(v, decimals: 2)

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

  defp row_style(expanded) do
    base = "cursor: pointer;"
    if expanded, do: base <> " background: #eff6ff;", else: base
  end

  defp pre_style do
    "background: #111827; color: #f9fafb; padding: 0.75rem; border-radius: 4px; " <>
      "font-size: 0.8rem; overflow-x: auto; white-space: pre-wrap; margin: 0.25rem 0 0 0;"
  end
end
