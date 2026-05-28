defmodule MehungryWeb.ProfessionalLive.AnalyticsLive do
  use MehungryWeb, :live_view

  alias Mehungry.Meta
  alias VegaLite, as: Vl

  @presence_topic "general"
  @analytics_topic "mehungry:analytics"
  @refresh_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MehungryWeb.Endpoint.subscribe(@presence_topic)
      Phoenix.PubSub.subscribe(Mehungry.PubSub, @analytics_topic)
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    {:ok, socket |> load_stats() |> assign_online_count()}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign_online_count(socket)}
  end

  @impl true
  def handle_info(:new_visit, socket) do
    {:noreply, load_stats(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load_stats(socket)}
  end

  defp load_stats(socket) do
    today = Meta.stats_today()
    totals = Meta.total_stats()
    daily_data = Meta.visits_per_day(14)
    source_data = Meta.traffic_sources(30)

    assign(socket,
      today_total: today.total,
      today_unique: today.unique_ips,
      all_total: totals.total,
      all_unique: totals.unique_ips,
      top_pages: Meta.top_pages(10),
      recent_visits: Meta.recent_visits(40),
      traffic_sources: source_data,
      daily_chart_spec: build_daily_spec(daily_data),
      source_chart_spec: build_source_spec(source_data)
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

  # ---------- Chart builders ----------

  defp build_daily_spec(data) do
    chart_data =
      Enum.map(data, fn %{date: d, count: c} -> %{"date" => to_string(d), "visits" => c} end)

    Vl.new(width: :container, height: 160)
    |> Vl.data_from_values(chart_data)
    |> Vl.mark(:bar, color: "#EA580C", corner_radius_end: 3)
    |> Vl.encode_field(:x, "date", type: :ordinal,
      axis: [label_angle: -35, title: nil, label_color: "#94A3B8", domain_color: "#334155", tick_color: "#334155"]
    )
    |> Vl.encode_field(:y, "visits", type: :quantitative,
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", grid_color: "#1E293B"]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_source_spec(data) when data == [] do
    Vl.new(width: :container, height: 160)
    |> Vl.data_from_values([%{"source" => "no data", "count" => 0}])
    |> Vl.mark(:bar)
    |> Vl.encode_field(:y, "source", type: :nominal)
    |> Vl.encode_field(:x, "count", type: :quantitative)
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_source_spec(data) do
    Vl.new(width: :container, height: 160)
    |> Vl.data_from_values(data)
    |> Vl.mark(:bar, corner_radius_end: 3)
    |> Vl.encode_field(:y, "source", type: :nominal,
      sort: "-x",
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", tick_color: "#334155"]
    )
    |> Vl.encode_field(:x, "count", type: :quantitative,
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", grid_color: "#1E293B"]
    )
    |> Vl.encode_field(:color, "source",
      type: :nominal,
      legend: nil,
      scale: [
        domain: ["direct", "search", "social", "referral", "internal"],
        range: ["#64748B", "#EA580C", "#3B82F6", "#8B5CF6", "#10B981"]
      ]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  # ---------- Render helpers ----------

  def source_badge_class("search"), do: "bg-primary-500/20 text-primary-400 border-primary-500/30"
  def source_badge_class("social"), do: "bg-blue-500/20 text-blue-400 border-blue-500/30"
  def source_badge_class("referral"), do: "bg-purple-500/20 text-purple-400 border-purple-500/30"
  def source_badge_class("internal"), do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30"
  def source_badge_class(_), do: "bg-slate-700 text-slate-400 border-slate-600"

  def source_label("search"), do: "Search"
  def source_label("social"), do: "Social"
  def source_label("referral"), do: "Referral"
  def source_label("internal"), do: "Internal"
  def source_label(_), do: "Direct"

  def visit_source(visit) do
    ref = get_in(visit.details || %{}, ["referrer"]) || ""
    Meta.classify_referrer(ref) |> Atom.to_string()
  end

  def short_path(nil), do: "Home"
  def short_path(""), do: "Home"

  def short_path(path) do
    path
    |> String.replace(MehungryWeb.Endpoint.url(), "")
    |> case do
      "" -> "Home"
      "/" -> "Home"
      p -> p
    end
  end

  def short_agent(nil), do: "—"
  def short_agent(""), do: "—"

  def short_agent(agent) do
    cond do
      String.contains?(agent, "Googlebot") -> "Googlebot"
      String.contains?(agent, "bingbot") -> "Bingbot"
      String.contains?(agent, "iPhone") -> "iPhone"
      String.contains?(agent, "Android") -> "Android"
      String.contains?(agent, "Chrome") -> "Chrome"
      String.contains?(agent, "Firefox") -> "Firefox"
      String.contains?(agent, "Safari") -> "Safari"
      true -> String.slice(agent, 0, 30)
    end
  end

  def format_dt(nil), do: "—"

  def format_dt(dt) do
    "#{pad(dt.hour)}:#{pad(dt.minute)} #{dt.day}/#{dt.month}"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
