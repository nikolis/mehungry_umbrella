defmodule MehungryWeb.ProfessionalLive.SeoLive do
  use MehungryWeb, :live_view

  alias Mehungry.Meta
  alias VegaLite, as: Vl

  @analytics_topic "mehungry:analytics"
  @refresh_ms 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, @analytics_topic)
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    {:ok, socket |> assign(:days, 30) |> load_seo_stats()}
  end

  @impl true
  def handle_event("set_days", %{"days" => d}, socket) do
    days = String.to_integer(d)
    {:noreply, socket |> assign(:days, days) |> load_seo_stats()}
  end

  def handle_event("resize_chart", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:new_visit, socket) do
    {:noreply, load_seo_stats(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load_seo_stats(socket)}
  end

  defp load_seo_stats(socket) do
    days = socket.assigns.days
    organic_daily = Meta.organic_visits_per_day(days)
    engine_breakdown = Meta.search_engine_breakdown(days)
    crawlers = Meta.crawler_activity(7)
    landing_pages = Meta.organic_landing_pages(days)
    queries = Meta.search_queries_extracted(days)

    organic_total = Enum.sum(Enum.map(organic_daily, & &1.count))

    # Week-over-week change
    half = div(days, 2)
    cutoff_recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -(half * 86_400), :second)
    _cutoff_past = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    {recent_organic, past_organic} =
      organic_daily
      |> Enum.split_with(fn %{date: d} ->
        NaiveDateTime.compare(NaiveDateTime.new!(d, ~T[00:00:00]), cutoff_recent) in [:gt, :eq]
      end)

    recent_count = Enum.sum(Enum.map(recent_organic, & &1.count))
    past_count = Enum.sum(Enum.map(past_organic, & &1.count))

    trend_pct =
      if past_count == 0 do
        if recent_count > 0, do: 100, else: 0
      else
        round((recent_count - past_count) / past_count * 100)
      end

    assign(socket,
      organic_total: organic_total,
      trend_pct: trend_pct,
      engine_breakdown: engine_breakdown,
      crawlers: crawlers,
      landing_pages: landing_pages,
      queries: queries,
      organic_chart_spec: build_organic_spec(organic_daily),
      engine_chart_spec: build_engine_spec(engine_breakdown),
      crawler_summary: group_crawlers(crawlers)
    )
  end

  # ---------- Chart builders ----------

  defp build_organic_spec([]) do
    Vl.new(width: :container, height: 180)
    |> Vl.data_from_values([%{"date" => "—", "visits" => 0}])
    |> Vl.mark(:bar)
    |> Vl.encode_field(:x, "date", type: :ordinal)
    |> Vl.encode_field(:y, "visits", type: :quantitative)
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_organic_spec(data) do
    chart_data =
      Enum.map(data, fn %{date: d, count: c} -> %{"date" => to_string(d), "visits" => c} end)

    Vl.new(width: :container, height: 180)
    |> Vl.data_from_values(chart_data)
    |> Vl.mark(:area,
      color: "#EA580C",
      fill_opacity: 0.15,
      line: %{color: "#EA580C", stroke_width: 2},
      point: %{filled: true, fill: "#EA580C", size: 40}
    )
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
    |> Vl.encode_field(:y, "visits",
      type: :quantitative,
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", grid_color: "#1E293B"]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_engine_spec([]) do
    Vl.new(width: :container, height: 160)
    |> Vl.data_from_values([%{"engine" => "no data", "count" => 0}])
    |> Vl.mark(:bar)
    |> Vl.encode_field(:y, "engine", type: :nominal)
    |> Vl.encode_field(:x, "count", type: :quantitative)
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_engine_spec(data) do
    Vl.new(width: :container, height: 160)
    |> Vl.data_from_values(data)
    |> Vl.mark(:bar, corner_radius_end: 3)
    |> Vl.encode_field(:y, "engine",
      type: :nominal,
      sort: "-x",
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", tick_color: "#334155"]
    )
    |> Vl.encode_field(:x, "count",
      type: :quantitative,
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", grid_color: "#1E293B"]
    )
    |> Vl.encode_field(:color, "engine",
      type: :nominal,
      legend: nil,
      scale: [
        domain: ["Google", "Bing", "DuckDuckGo", "Yahoo", "Ecosia", "Brave", "Yandex", "Other"],
        range: [
          "#4285F4",
          "#00897B",
          "#DE5833",
          "#720E9E",
          "#4CAF50",
          "#FB8C00",
          "#CC0000",
          "#64748B"
        ]
      ]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp group_crawlers(visits) do
    visits
    |> Enum.group_by(fn v -> Meta.crawler_name(get_in(v.details || %{}, ["agent"]) || "") end)
    |> Enum.map(fn {name, visits} ->
      last = visits |> Enum.max_by(& &1.inserted_at, NaiveDateTime) |> Map.get(:inserted_at)
      %{name: name, count: length(visits), last_seen: last}
    end)
    |> Enum.sort_by(& &1.last_seen, {:desc, NaiveDateTime})
  end

  # ---------- Render helpers ----------

  def trend_color(pct) when pct > 0, do: "text-emerald-400"
  def trend_color(pct) when pct < 0, do: "text-red-400"
  def trend_color(_), do: "text-slate-400"

  def trend_arrow(pct) when pct > 0, do: "↑"
  def trend_arrow(pct) when pct < 0, do: "↓"
  def trend_arrow(_), do: "→"

  def engine_dot_color("Google"), do: "bg-blue-400"
  def engine_dot_color("Bing"), do: "bg-teal-400"
  def engine_dot_color("DuckDuckGo"), do: "bg-orange-400"
  def engine_dot_color("Yahoo"), do: "bg-purple-400"
  def engine_dot_color("Ecosia"), do: "bg-green-400"
  def engine_dot_color("Brave"), do: "bg-orange-500"
  def engine_dot_color(_), do: "bg-slate-500"

  def crawler_dot_color("Googlebot"), do: "text-blue-400"
  def crawler_dot_color("Bingbot"), do: "text-teal-400"
  def crawler_dot_color(_), do: "text-slate-400"

  def short_path(nil), do: "Home"
  def short_path(""), do: "Home"

  def short_path(p) do
    p
    |> String.replace(MehungryWeb.Endpoint.url(), "")
    |> then(fn
      "" -> "Home"
      "/" -> "Home"
      x -> x
    end)
  end

  def format_dt(nil), do: "—"

  def format_dt(dt) do
    "#{pad(dt.day)}/#{pad(dt.month)} #{pad(dt.hour)}:#{pad(dt.minute)}"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
