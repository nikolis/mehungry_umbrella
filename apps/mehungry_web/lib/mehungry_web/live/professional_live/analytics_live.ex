defmodule MehungryWeb.ProfessionalLive.AnalyticsLive do
  use MehungryWeb, :live_view

  alias Mehungry.Meta
  alias VegaLite, as: Vl

  @presence_topic "general"
  @analytics_topic "mehungry:analytics"
  @refresh_ms 30_000
  @visit_batch 60

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      MehungryWeb.Endpoint.subscribe(@presence_topic)
      Phoenix.PubSub.subscribe(Mehungry.PubSub, @analytics_topic)
      Process.send_after(self(), :refresh, @refresh_ms)
    end

    socket =
      socket
      |> assign(filter_category: nil, filter_source: nil,
                 visit_offset: 0, filtered_visits: [], visits_exhausted: false,
                 available_sources: [], selected_session_idx: 0)
      |> load_stats()
      |> assign_online_count()
      |> init_visits()

    {:ok, socket}
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

  @impl true
  def handle_event("resize_chart", %{"width" => width}, socket) when width > 50 do
    daily_data = Meta.visits_per_day(14)
    source_data = Meta.traffic_sources(30)

    {:noreply,
     assign(socket,
       daily_chart_spec: build_daily_spec(daily_data, width),
       source_chart_spec: build_source_spec(source_data, width)
     )}
  end

  def handle_event("resize_chart", _params, socket), do: {:noreply, socket}

  def handle_event("load-more", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_session", %{"idx" => idx}, socket) do
    {:noreply, assign(socket, :selected_session_idx, String.to_integer(idx))}
  end

  @impl true
  def handle_event("set_filter_category", %{"category" => cat}, socket) do
    new_cat = if cat == socket.assigns.filter_category, do: nil, else: cat
    {:noreply, socket |> assign(filter_category: new_cat, filter_source: nil) |> reload_visits()}
  end

  @impl true
  def handle_event("set_filter_source", %{"source" => src}, socket) do
    new_src = if src == socket.assigns.filter_source, do: nil, else: src
    {:noreply, socket |> assign(filter_source: new_src, filter_category: nil) |> reload_visits()}
  end

  @impl true
  def handle_event("clear_visit_filter", _params, socket) do
    {:noreply, socket |> assign(filter_category: nil, filter_source: nil) |> reload_visits()}
  end

  @impl true
  def handle_event("load_more_visits", _params, socket) do
    if socket.assigns.visits_exhausted do
      {:noreply, socket}
    else
      {:noreply, fetch_more_visits(socket)}
    end
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
      sessions: Meta.recent_sessions(30, 7),
      daily_chart_spec: build_daily_spec(daily_data),
      source_chart_spec: build_source_spec(source_data)
    )
  end

  defp init_visits(socket) do
    available =
      Meta.distinct_referrers(30)
      |> Enum.map(&specific_source/1)
      |> Enum.uniq()
      |> Enum.sort()

    socket
    |> assign(:available_sources, available)
    |> reload_visits()
  end

  defp reload_visits(socket) do
    raw = Meta.recent_visits_page(@visit_batch, 0)
    filtered = apply_visit_filters(raw, socket.assigns.filter_category, socket.assigns.filter_source)

    assign(socket,
      filtered_visits: filtered,
      visit_offset: length(raw),
      visits_exhausted: length(raw) < @visit_batch
    )
  end

  defp fetch_more_visits(socket) do
    raw = Meta.recent_visits_page(@visit_batch, socket.assigns.visit_offset)
    filtered = apply_visit_filters(raw, socket.assigns.filter_category, socket.assigns.filter_source)

    assign(socket,
      filtered_visits: socket.assigns.filtered_visits ++ filtered,
      visit_offset: socket.assigns.visit_offset + length(raw),
      visits_exhausted: length(raw) < @visit_batch
    )
  end

  defp apply_visit_filters(visits, nil, nil), do: visits

  defp apply_visit_filters(visits, category, nil) do
    Enum.filter(visits, fn v -> visit_source(v) == category end)
  end

  defp apply_visit_filters(visits, nil, source) do
    Enum.filter(visits, fn v ->
      ref = get_in(v.details || %{}, ["referrer"]) || ""
      specific_source(ref) == source
    end)
  end

  defp apply_visit_filters(visits, category, source) do
    Enum.filter(visits, fn v ->
      visit_source(v) == category and
        specific_source(get_in(v.details || %{}, ["referrer"]) || "") == source
    end)
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

  defp build_daily_spec(data, width \\ :container) do
    chart_data =
      Enum.map(data, fn %{date: d, count: c} -> %{"date" => to_string(d), "visits" => c} end)

    Vl.new(width: width, height: 160)
    |> Vl.data_from_values(chart_data)
    |> Vl.mark(:bar, color: "#EA580C", corner_radius_end: 3)
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

  defp build_source_spec(data, width \\ :container)

  defp build_source_spec(data, width) when data == [] do
    Vl.new(width: width, height: 160)
    |> Vl.data_from_values([%{"source" => "no data", "count" => 0}])
    |> Vl.mark(:bar)
    |> Vl.encode_field(:y, "source", type: :nominal)
    |> Vl.encode_field(:x, "count", type: :quantitative)
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_source_spec(data, width) do
    Vl.new(width: width, height: 160)
    |> Vl.data_from_values(data)
    |> Vl.mark(:bar, corner_radius_end: 3)
    |> Vl.encode_field(:y, "source",
      type: :nominal,
      sort: "-x",
      axis: [title: nil, label_color: "#94A3B8", domain_color: "#334155", tick_color: "#334155"]
    )
    |> Vl.encode_field(:x, "count",
      type: :quantitative,
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

  def source_badge_class("internal"),
    do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30"

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

  def specific_source(nil), do: "Direct"
  def specific_source(""), do: "Direct"

  def specific_source(ref) do
    cond do
      String.contains?(ref, "google.") -> "Google"
      String.contains?(ref, "bing.com") -> "Bing"
      String.contains?(ref, "duckduckgo.com") -> "DuckDuckGo"
      String.contains?(ref, "yahoo.com") -> "Yahoo"
      String.contains?(ref, "yandex.") -> "Yandex"
      String.contains?(ref, "baidu.com") -> "Baidu"
      String.contains?(ref, "ecosia.org") -> "Ecosia"
      String.contains?(ref, "search.brave.com") -> "Brave Search"
      String.contains?(ref, "facebook.com") -> "Facebook"
      String.contains?(ref, "instagram.com") -> "Instagram"
      String.contains?(ref, "twitter.com") or String.contains?(ref, "t.co") -> "Twitter/X"
      String.contains?(ref, "linkedin.com") -> "LinkedIn"
      String.contains?(ref, "reddit.com") -> "Reddit"
      String.contains?(ref, "pinterest.com") -> "Pinterest"
      String.contains?(ref, "tiktok.com") -> "TikTok"
      String.contains?(ref, "youtube.com") -> "YouTube"
      String.contains?(ref, "mehungry") -> "Internal"
      true -> referrer_domain(ref)
    end
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
      String.contains?(agent, "DuckDuckBot") -> "DuckDuckBot"
      String.contains?(agent, "YandexBot") -> "YandexBot"
      String.contains?(agent, "AhrefsBot") -> "AhrefsBot"
      String.contains?(agent, "SemrushBot") -> "SemrushBot"
      String.contains?(agent, "facebookexternalhit") -> "FacebookBot"
      String.contains?(agent, "Twitterbot") -> "Twitterbot"
      String.contains?(agent, "iPhone") -> "Safari/iPhone"
      String.contains?(agent, "iPad") -> "Safari/iPad"
      String.contains?(agent, "Android") and String.contains?(agent, "Chrome") -> "Chrome/Android"
      String.contains?(agent, "Android") -> "Android Browser"
      String.contains?(agent, "Edg/") -> "Edge"
      String.contains?(agent, "OPR/") or String.contains?(agent, "Opera") -> "Opera"
      String.contains?(agent, "Firefox") -> "Firefox"
      String.contains?(agent, "Chrome") -> "Chrome"
      String.contains?(agent, "Safari") -> "Safari"
      true -> String.slice(agent, 0, 30)
    end
  end

  def detect_os(nil), do: "—"
  def detect_os(""), do: "—"

  def detect_os(agent) do
    cond do
      String.contains?(agent, "Windows NT 10") -> "Win 10/11"
      String.contains?(agent, "Windows NT 6.3") -> "Win 8.1"
      String.contains?(agent, "Windows NT 6.1") -> "Win 7"
      String.contains?(agent, "Windows") -> "Windows"
      String.contains?(agent, "iPhone OS") ->
        case Regex.run(~r/iPhone OS (\d+)_/, agent) do
          [_, v] -> "iOS #{v}"
          _ -> "iOS"
        end
      String.contains?(agent, "iPad") ->
        case Regex.run(~r/OS (\d+)_/, agent) do
          [_, v] -> "iPadOS #{v}"
          _ -> "iPadOS"
        end
      String.contains?(agent, "Android") ->
        case Regex.run(~r/Android (\d+)/, agent) do
          [_, v] -> "Android #{v}"
          _ -> "Android"
        end
      String.contains?(agent, "Mac OS X") ->
        case Regex.run(~r/Mac OS X (\d+)[_.](\d+)/, agent) do
          [_, maj, min] -> "macOS #{maj}.#{min}"
          _ -> "macOS"
        end
      String.contains?(agent, "Linux") -> "Linux"
      true -> "—"
    end
  end

  def detect_device(nil), do: "desktop"
  def detect_device(""), do: "desktop"

  def detect_device(agent) do
    cond do
      String.contains?(agent, "Googlebot") or String.contains?(agent, "bot") or
          String.contains?(agent, "Bot") or String.contains?(agent, "Crawler") ->
        "bot"
      String.contains?(agent, "iPhone") or String.contains?(agent, "Android") and
          not String.contains?(agent, "Tablet") ->
        "mobile"
      String.contains?(agent, "iPad") or String.contains?(agent, "Tablet") ->
        "tablet"
      true ->
        "desktop"
    end
  end

  def device_icon("mobile"), do: "hero-device-phone-mobile"
  def device_icon("tablet"), do: "hero-device-tablet"
  def device_icon("bot"), do: "hero-cpu-chip"
  def device_icon(_), do: "hero-computer-desktop"

  def referrer_domain(nil), do: "—"
  def referrer_domain(""), do: "direct"

  def referrer_domain(ref) do
    case URI.parse(ref) do
      %URI{host: host} when not is_nil(host) ->
        host |> String.replace_prefix("www.", "")
      _ ->
        String.slice(ref, 0, 40)
    end
  end

  def format_page_time(nil), do: nil
  def format_page_time(0), do: "< 1s"
  def format_page_time(sec) when sec < 60, do: "#{sec}s"
  def format_page_time(sec), do: "#{div(sec, 60)}m #{rem(sec, 60)}s"

  def session_identity(%{user_email: email}) when is_binary(email) and email != "", do: email
  def session_identity(%{user_id: id}) when not is_nil(id), do: "User ##{id}"
  def session_identity(%{ip_address: ip}), do: "Anon · #{ip}"

  def session_duration(%{duration_min: 0, duration_sec: s}), do: "#{s}s"
  def session_duration(%{duration_min: m, duration_sec: 0}), do: "#{m}m"
  def session_duration(%{duration_min: m, duration_sec: s}), do: "#{m}m #{s}s"

  def short_session_key(nil), do: "—"
  def short_session_key(key), do: String.slice(key, 0, 8)

  def format_dt(nil), do: "—"

  def format_dt(dt) do
    "#{pad(dt.hour)}:#{pad(dt.minute)} #{dt.day}/#{dt.month}"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
