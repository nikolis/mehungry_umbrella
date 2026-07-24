defmodule MehungryWeb.ErrorsPage do
  use Phoenix.LiveDashboard.PageBuilder
  import MehungryWeb.FormatHelpers, only: [truncate: 2]
  import Ecto.Query

  @limit 100

  @impl true
  def menu_link(_, _), do: {:ok, "Errors"}

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, errors: fetch_errors(), expanded: nil, limit: @limit)}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, assign(socket, errors: fetch_errors())}
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
      <div style="margin-bottom: 1rem; color: #6b7280; font-size: 0.85rem;">
        {length(@errors)} distinct errors (last {@limit}, grouped by fingerprint) · retained 30 days · click a row for details
      </div>

      <%= if @errors == [] do %>
        <p style="color: #6b7280; font-style: italic;">No errors recorded. 🎉</p>
      <% else %>
        <div style="overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem;">
            <thead>
              <tr style="border-bottom: 2px solid #e5e7eb; text-align: left;">
                <th style={th_style()}>Source</th>
                <th style={th_style()}>Kind</th>
                <th style={th_style()}>Reason</th>
                <th style={th_style(:right)}>Count</th>
                <th style={th_style()}>First seen (UTC)</th>
                <th style={th_style()}>Last seen (UTC)</th>
              </tr>
            </thead>
            <tbody>
              <%= for error <- @errors do %>
                <tr
                  phx-click="toggle"
                  phx-value-fingerprint={error.fingerprint}
                  style={row_style(@expanded == error.fingerprint)}
                >
                  <td style={td_style()}>{source_badge(error.source)}</td>
                  <td style={td_style()}><code>{error.kind}</code></td>
                  <td style={td_style()}>{truncate(error.reason, 120)}</td>
                  <td style={td_style(:right)}><strong>{error.count}</strong></td>
                  <td style={td_style()}>{format_dt(error.first_seen)}</td>
                  <td style={td_style()}>{format_dt(error.last_seen)}</td>
                </tr>
                <%= if @expanded == error.fingerprint do %>
                  <tr>
                    <td
                      colspan="6"
                      style="padding: 0.75rem; background: #f9fafb; border-bottom: 1px solid #e5e7eb;"
                    >
                      <div style="margin-bottom: 0.5rem;">
                        <strong>Context:</strong> {format_context(error.context)}
                      </div>
                      <div style="margin-bottom: 0.5rem;">
                        <strong>Reason:</strong>
                        <pre style={pre_style()}><%= error.reason %></pre>
                      </div>
                      <div>
                        <strong>Stacktrace:</strong>
                        <pre style={pre_style()}><%= error.stacktrace %></pre>
                      </div>
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

  defp fetch_errors do
    Mehungry.Repo.all(
      from(e in Mehungry.Telemetry.ErrorEvent,
        order_by: [desc: e.last_seen],
        limit: @limit
      )
    )
  rescue
    _ -> []
  end

  # --- Formatting helpers ---

  defp format_dt(nil), do: "—"

  defp format_dt(dt) do
    "#{dt.year}-#{pad(dt.month)}-#{pad(dt.day)} #{pad(dt.hour)}:#{pad(dt.minute)}"
  end

  defp pad(n), do: String.pad_leading(to_string(n), 2, "0")

  defp format_context(context) when map_size(context) == 0, do: "—"

  defp format_context(context) do
    context
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end

  defp source_badge(source), do: source

  # --- Style helpers ---

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
