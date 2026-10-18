defmodule MehungryWeb.ProfessionalLive.AnalyticsLive do
  @moduledoc """
  Slim traffic view. Everything that duplicated Google Analytics (traffic
  sources, page views, device/OS, session journeys, referrer tables) was
  removed — GA4 + Search Console own that. What's left is the one thing GA4
  can't give: a consent-independent anonymous-session count (the honest
  denominator that includes visitors who declined the cookie banner), plus a
  free real-time "online now" from Presence.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Meta
  alias VegaLite, as: Vl

  @presence_topic "general"
  @refresh_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MehungryWeb.Endpoint.subscribe(@presence_topic)
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    {:ok, socket |> load_stats() |> assign_online_count()}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign_online_count(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load_stats(socket)}
  end

  @impl true
  def handle_event("resize_chart", %{"width" => width}, socket) when width > 50 do
    session_daily = Meta.session_metrics_per_day(14)
    {:noreply, assign(socket, session_chart_spec: build_session_spec(session_daily, width))}
  end

  def handle_event("resize_chart", _params, socket), do: {:noreply, socket}

  defp load_stats(socket) do
    session_today = Meta.session_metrics_today()
    session_daily = Meta.session_metrics_per_day(14)

    assign(socket,
      anon_sessions_today: session_today.sessions,
      anon_avg_session: format_mmss(session_today.avg_seconds),
      session_chart_spec: build_session_spec(session_daily)
    )
  end

  defp assign_online_count(socket) do
    count =
      case Map.get(MehungryWeb.Presence.list("general"), "general") do
        nil -> 0
        %{metas: metas} -> length(metas)
      end

    assign(socket, :online_count, count)
  end

  # Anonymous sessions per day (consent-independent). Basil/emerald tone.
  defp build_session_spec(data, width \\ :container) do
    chart_data =
      Enum.map(data, fn %{date: d, session_count: c} ->
        %{"date" => to_string(d), "sessions" => c}
      end)

    Vl.new(width: width, height: 200, autosize: [type: "fit", contains: "padding"])
    |> Vl.data_from_values(chart_data)
    |> Vl.mark(:bar, color: "#10B981", corner_radius_end: 3)
    |> Vl.encode_field(:x, "date",
      type: :ordinal,
      axis: [
        label_angle: -35,
        title: nil,
        label_color: "#94A3B8",
        domain_color: "#334155",
        tick_color: "#334155"
      ]
    )
    |> Vl.encode_field(:y, "sessions",
      type: :quantitative,
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", grid_color: "#1E293B"]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  # mm:ss from a whole number of seconds (for average session length).
  def format_mmss(seconds) when is_integer(seconds) and seconds >= 60 do
    "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  end

  def format_mmss(seconds) when is_integer(seconds), do: "#{seconds}s"
  def format_mmss(_), do: "0s"
end
