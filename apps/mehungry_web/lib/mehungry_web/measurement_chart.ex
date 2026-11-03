defmodule MehungryWeb.MeasurementChart do
  @moduledoc """
  The client body-measurement **progress dashboard**, shared by the nutritionist
  client file (`ClientDetail`) and the client's own profile (`ProfileLive`).

  A measurement history is `[%{date: ~D[...], source:, <metric> => number | nil}]`
  as returned by `Mehungry.Professionals.measurement_history/1`, plus a static
  reference `context` (`%{height_m:, sex:, ideal_weight_kg:}` from the latest
  intake, via `Professionals.measurement_context/1`) used to draw grounded goal
  lines and healthy bands.

  Rendering is **hand-built inline SVG**, not a JS charting library: the data is
  tiny (a handful of points), the layout is a KPI-card grid + a single focused
  trend chart (which no declarative chart grammar expresses cleanly), and SVG
  server-renders instantly with pixel-exact design-token theming and no
  connect round-trip. Each metric has its own unit, so the detail chart shows
  **one metric at a time** (a shared y-axis across kg / % / cm / kcal would
  mislead); the KPI cards surface every metric's headline + delta + sparkline at
  once. `progress_dashboard/1` is the function component the LiveViews embed.
  """

  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  # ── design tokens (these surfaces are always on the dark `ink-panel`) ──────────
  @c_basil "#45C4AE"
  @c_paprika "#E8622C"
  @c_grid "#332e20"
  @c_dim "#A9A08C"
  @c_panel "#211D16"
  @c_bad "#EF4444"

  # ── chart geometry (viewBox units; the <svg> scales to 100% width) ─────────────
  @w 680
  @h 280
  @ml 52
  @mr 20
  @mt 24
  @mb 44

  # metric key => {label, unit | nil}. Order is the selector/card display order.
  @metrics [
    {"weight_kg", {"Weight", "kg"}},
    {"body_fat_percentage", {"Body fat", "%"}},
    {"waist_cm", {"Waist", "cm"}},
    {"muscle_mass_kg", {"Muscle mass", "kg"}},
    {"bmi", {"BMI", nil}},
    {"bmr_kcal", {"BMR", "kcal"}}
  ]

  # Which direction of change reads as progress, so a delta can be tinted. `:none`
  # metrics (BMR) are never judged — the arrow still shows the real direction.
  @good_direction %{
    "weight_kg" => :down,
    "body_fat_percentage" => :down,
    "waist_cm" => :down,
    "muscle_mass_kg" => :up,
    "bmi" => :down,
    "bmr_kcal" => :none
  }

  @doc "All metric keys in display order."
  def metric_keys, do: Enum.map(@metrics, &elem(&1, 0))

  @doc "Display label for a metric key (e.g. `\"weight_kg\"` → `\"Weight\"`)."
  def metric_label(key) do
    case List.keyfind(@metrics, key, 0) do
      {_, {label, _unit}} -> label
      _ -> key
    end
  end

  @doc "Unit string for a metric key, or `nil` (e.g. BMI)."
  def metric_unit(key) do
    case List.keyfind(@metrics, key, 0) do
      {_, {_label, unit}} -> unit
      _ -> nil
    end
  end

  @doc """
  The metric keys that have **at least 2** dated points in `history` (enough to
  draw a trend), in display order.
  """
  def available_metrics(history) do
    Enum.filter(metric_keys(), fn key ->
      Enum.count(history, fn point -> point[String.to_existing_atom(key)] end) >= 2
    end)
  end

  @doc """
  Pick which metric to show: keep `current` if it's still available, else the
  first available, else `nil`.
  """
  def pick_metric(current, available) do
    cond do
      current && current in available -> current
      available != [] -> hd(available)
      true -> nil
    end
  end

  # ── KPI cards ──────────────────────────────────────────────────────────────────

  @doc """
  One KPI-card map per available metric: current value, since-baseline delta
  (value + direction arrow + good/bad/flat tone) and a sparkline SVG.
  """
  def cards(history) do
    Enum.map(available_metrics(history), &card(history, &1))
  end

  defp card(history, key) do
    pts = present_points(history, key)
    first = List.first(pts).value
    last = List.last(pts).value
    delta = last - first
    tone = tone(key, delta)

    %{
      key: key,
      label: metric_label(key),
      unit: metric_unit(key) || "",
      current: fmt_num(last),
      current_display: fmt_num(last) <> maybe_unit(metric_unit(key)),
      delta_abs: fmt_num(abs(delta)) <> maybe_unit(delta_unit(key)),
      arrow: arrow(delta),
      tone: tone,
      spark: sparkline_svg(pts, tone_color(tone))
    }
  end

  defp tone(key, delta) do
    case {@good_direction[key], delta} do
      {:none, _} -> :flat
      {_, 0} -> :flat
      {:down, d} when d < 0 -> :good
      {:up, d} when d > 0 -> :good
      _ -> :bad
    end
  end

  defp tone_color(:good), do: @c_basil
  defp tone_color(:bad), do: @c_bad
  defp tone_color(_), do: @c_dim

  defp arrow(d) when d < 0, do: "▼"
  defp arrow(d) when d > 0, do: "▲"
  defp arrow(_), do: "–"

  defp delta_unit("body_fat_percentage"), do: "pt"
  defp delta_unit(key), do: metric_unit(key)

  # ── goal line / healthy band (grounded in the client's intake) ─────────────────

  @doc "A goal reference value for `key` from `context`, or `nil`."
  def goal(context, "weight_kg") do
    case context[:ideal_weight_kg] do
      w when is_number(w) and w > 0 -> w * 1.0
      _ -> nil
    end
  end

  def goal(_context, _key), do: nil

  @doc "A `{low, high}` healthy band for `key` from `context`, or `nil`."
  def band(_context, "bmi"), do: {18.5, 24.9}

  def band(context, "weight_kg") do
    case context[:height_m] do
      h when is_number(h) and h > 0 ->
        {Float.round(18.5 * h * h, 1), Float.round(24.9 * h * h, 1)}

      _ ->
        nil
    end
  end

  def band(context, "body_fat_percentage") do
    case context[:sex] do
      "male" -> {10.0, 20.0}
      "female" -> {18.0, 28.0}
      _ -> nil
    end
  end

  def band(_context, _key), do: nil

  @doc "Legend entries to show for `key`: `:intake`/`:visit` always, plus `:goal`/`:band` when present."
  def legend_items(context, nil), do: legend_items(context, "weight_kg") |> List.delete(:goal) |> List.delete(:band)

  def legend_items(context, key) do
    [:intake, :visit] ++
      if(goal(context, key), do: [:goal], else: []) ++
      if(band(context, key), do: [:band], else: [])
  end

  # ── detail trend chart ─────────────────────────────────────────────────────────

  @doc """
  The focused single-metric trend chart as a raw SVG (area + line, intake/visit
  points, emphasized latest reading, healthy band + goal line where grounded).
  Returns `nil` when `metric` is nil or has fewer than 2 points.
  """
  def chart_svg(_history, nil, _context), do: nil

  def chart_svg(history, metric, context) do
    context = context || %{}
    pts = present_points(history, metric)

    if length(pts) < 2 do
      nil
    else
      build_chart(pts, metric, context)
    end
  end

  defp build_chart(pts, metric, context) do
    plot_w = @w - @ml - @mr
    plot_h = @h - @mt - @mb
    base = @mt + plot_h

    dates = Enum.map(pts, & &1.date)
    min_d = List.first(dates)
    max_d = List.last(dates)
    span = Date.diff(max_d, min_d)

    x_of = fn d ->
      if span == 0, do: @ml + plot_w / 2, else: @ml + Date.diff(d, min_d) / span * plot_w
    end

    band = band(context, metric)
    goal = goal(context, metric)
    extras = (if band, do: Tuple.to_list(band), else: []) ++ List.wrap(goal)
    all = Enum.map(pts, &(&1.value * 1.0)) ++ extras
    {lo0, hi0} = Enum.min_max(all)
    pad = if hi0 - lo0 == 0, do: max(abs(hi0) * 0.05, 1.0), else: (hi0 - lo0) * 0.14
    lo = lo0 - pad
    hi = hi0 + pad
    y_of = fn v -> @mt + (hi - v) / (hi - lo) * plot_h end

    coords = Enum.map(pts, fn p -> {x_of.(p.date), y_of.(p.value * 1.0)} end)
    title = if metric_unit(metric), do: "#{metric_label(metric)} (#{metric_unit(metric)})", else: metric_label(metric)

    svg =
      ~s(<svg viewBox="0 0 #{@w} #{@h}" class="w-full h-auto block" font-family="ui-sans-serif, system-ui, sans-serif" role="img" aria-label="#{title} over time">) <>
        area_gradient_def() <>
        band_svg(band, y_of, plot_w) <>
        gridlines_svg(lo, hi, y_of, plot_w) <>
        goal_svg(goal, y_of, plot_w) <>
        area_line_svg(coords, base) <>
        points_svg(coords, pts) <>
        x_labels_svg(pts, x_of, base) <>
        y_title_svg(title, plot_h) <>
        "</svg>"

    raw(svg)
  end

  defp area_gradient_def do
    ~s(<defs><linearGradient id="mc-area" x1="0" y1="0" x2="0" y2="1">) <>
      ~s(<stop offset="0%" stop-color="#{@c_basil}" stop-opacity="0.26"/>) <>
      ~s(<stop offset="100%" stop-color="#{@c_basil}" stop-opacity="0"/></linearGradient></defs>)
  end

  defp band_svg(nil, _y_of, _plot_w), do: ""

  defp band_svg({blo, bhi}, y_of, plot_w) do
    y1 = y_of.(bhi)
    y2 = y_of.(blo)

    ~s(<rect x="#{@ml}" y="#{f(y1)}" width="#{plot_w}" height="#{f(y2 - y1)}" fill="#{@c_basil}" opacity="0.1"/>) <>
      ~s(<text x="#{@ml + plot_w - 6}" y="#{f(y1 + 13)}" text-anchor="end" fill="#{@c_basil}" opacity="0.8" font-size="10.5">healthy range</text>)
  end

  defp gridlines_svg(lo, hi, y_of, plot_w) do
    Enum.map_join(0..4, fn t ->
      v = lo + (hi - lo) * t / 4
      y = y_of.(v)

      ~s(<line x1="#{@ml}" y1="#{f(y)}" x2="#{@ml + plot_w}" y2="#{f(y)}" stroke="#{@c_grid}" stroke-width="1"/>) <>
        ~s(<text x="#{@ml - 8}" y="#{f(y + 3.5)}" text-anchor="end" fill="#{@c_dim}" font-size="11">#{fmt_num(Float.round(v, 1))}</text>)
    end)
  end

  defp goal_svg(nil, _y_of, _plot_w), do: ""

  defp goal_svg(goal, y_of, plot_w) do
    gy = y_of.(goal)

    ~s(<line x1="#{@ml}" y1="#{f(gy)}" x2="#{@ml + plot_w}" y2="#{f(gy)}" stroke="#{@c_paprika}" stroke-width="1.6" stroke-dasharray="5 4"/>) <>
      ~s(<text x="#{@ml + 4}" y="#{f(gy - 6)}" fill="#{@c_paprika}" font-size="11" font-weight="600">goal #{fmt_num(Float.round(goal, 1))}</text>)
  end

  defp area_line_svg(coords, base) do
    line_d =
      coords
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{x, y}, i} -> "#{if i == 0, do: "M", else: "L"}#{f(x)} #{f(y)}" end)

    {x0, _} = List.first(coords)
    {xl, _} = List.last(coords)

    area_d =
      "M#{f(x0)} #{f(base)} " <>
        Enum.map_join(coords, " ", fn {x, y} -> "L#{f(x)} #{f(y)}" end) <>
        " L#{f(xl)} #{f(base)} Z"

    ~s|<path d="#{area_d}" fill="url(#mc-area)"/>| <>
      ~s(<path d="#{line_d}" fill="none" stroke="#{@c_basil}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>)
  end

  defp points_svg(coords, pts) do
    last_i = length(pts) - 1

    coords
    |> Enum.zip(pts)
    |> Enum.with_index()
    |> Enum.map_join(fn {{{x, y}, p}, i} ->
      cond do
        i == last_i ->
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="8" fill="#{@c_paprika}" opacity="0.18"/>) <>
            ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="4.3" fill="#{@c_paprika}" stroke="#{@c_panel}" stroke-width="1.5"/>)

        p.source == :intake ->
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="3.6" fill="#{@c_basil}"/>)

        true ->
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="3.6" fill="#{@c_panel}" stroke="#{@c_basil}" stroke-width="1.8"/>)
      end
    end)
  end

  defp x_labels_svg(pts, x_of, base) do
    n = length(pts)
    step = max(1, div(n - 1, 6))
    y = base + 16

    pts
    |> Enum.with_index()
    |> Enum.map_join(fn {p, i} ->
      if rem(i, step) == 0 or i == n - 1 do
        x = x_of.(p.date)

        ~s|<text x="#{f(x)}" y="#{y}" text-anchor="end" fill="#{@c_dim}" font-size="10.5" transform="rotate(-32 #{f(x)} #{y})">#{Calendar.strftime(p.date, "%b %d")}</text>|
      else
        ""
      end
    end)
  end

  defp y_title_svg(title, plot_h) do
    cy = @mt + plot_h / 2
    ~s|<text x="14" y="#{f(cy)}" text-anchor="middle" fill="#{@c_dim}" font-size="11" transform="rotate(-90 14 #{f(cy)})">#{title}</text>|
  end

  # ── sparkline (card thumbnail) ─────────────────────────────────────────────────

  defp sparkline_svg(pts, color) do
    w = 120
    h = 26
    pad = 3
    vals = Enum.map(pts, &(&1.value * 1.0))
    {mn, mx} = Enum.min_max(vals)
    range = if mx - mn == 0, do: 1.0, else: mx - mn
    n = length(pts)

    coords =
      pts
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        x = pad + if n == 1, do: (w - 2 * pad) / 2, else: i / (n - 1) * (w - 2 * pad)
        y = h - pad - (p.value * 1.0 - mn) / range * (h - 2 * pad)
        {x, y}
      end)

    points = Enum.map_join(coords, " ", fn {x, y} -> "#{f(x)},#{f(y)}" end)
    {lx, ly} = List.last(coords)

    raw(
      ~s(<svg viewBox="0 0 #{w} #{h}" preserveAspectRatio="none" class="block w-full mt-1.5" style="height:22px" aria-hidden="true">) <>
        ~s(<polyline points="#{points}" fill="none" stroke="#{color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>) <>
        ~s(<circle cx="#{f(lx)}" cy="#{f(ly)}" r="2.4" fill="#{color}"/>) <>
        "</svg>"
    )
  end

  # ── shared internals ───────────────────────────────────────────────────────────

  defp present_points(history, key) do
    atom = String.to_existing_atom(key)

    history
    |> Enum.filter(&(&1[atom] && &1.date))
    |> Enum.map(&%{date: &1.date, value: &1[atom], source: Map.get(&1, :source, :visit)})
    |> Enum.sort_by(& &1.date, Date)
  end

  defp maybe_unit(nil), do: ""
  defp maybe_unit(""), do: ""
  defp maybe_unit(u), do: " " <> u

  defp fmt_num(v) when is_integer(v), do: Integer.to_string(v)

  defp fmt_num(v) when is_float(v) do
    r = Float.round(v, 1)
    if r == Float.round(r, 0), do: Integer.to_string(trunc(r)), else: :erlang.float_to_binary(r, decimals: 1)
  end

  # Format a number as a 1-decimal SVG coordinate string.
  defp f(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)

  # ── dashboard component ────────────────────────────────────────────────────────

  @doc """
  The progress dashboard: a KPI-card grid (each card drives the detail chart via a
  `select_metric` event the host LiveView handles) above the focused trend chart
  for `selected`. Assumes `cards` is non-empty — the caller shows its own
  "not enough data" copy otherwise.
  """
  attr :cards, :list, required: true
  attr :selected, :string, default: nil
  attr :chart, :any, default: nil
  attr :legend, :list, default: []

  def progress_dashboard(assigns) do
    assigns = assign(assigns, :selected_card, Enum.find(assigns.cards, &(&1.key == assigns.selected)))

    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5 mb-5">
      <button
        :for={c <- @cards}
        type="button"
        phx-click="select_metric"
        phx-value-metric={c.key}
        aria-pressed={to_string(c.key == @selected)}
        class={[
          "text-left rounded-xl p-3 border transition flex flex-col gap-0.5 focus:outline-none focus:ring-2 focus:ring-paprika",
          if(c.key == @selected,
            do: "bg-[#2e2112] border-paprika",
            else: "bg-ink-panel2 border-ink-panel2 hover:border-paprika-soft"
          )
        ]}
      >
        <span class={[
          "text-[11px] uppercase tracking-wide font-semibold",
          if(c.key == @selected, do: "text-paprika", else: "text-parchment-dim")
        ]}>
          {c.label}
        </span>
        <span class="font-display text-xl text-parchment leading-tight tabular-nums">
          {c.current}<span :if={c.unit != ""} class="text-xs text-parchment-dim ml-0.5 font-sans">{c.unit}</span>
        </span>
        <span class={["text-xs font-semibold tabular-nums", tone_text(c.tone)]}>
          {c.arrow} {c.delta_abs}
        </span>
        {c.spark}
      </button>
    </div>

    <div :if={@selected_card} class="flex items-baseline gap-x-3 gap-y-1 flex-wrap mb-1">
      <span class="font-display text-parchment font-semibold">{@selected_card.label}</span>
      <span class="text-parchment-dim text-sm tabular-nums">{@selected_card.current_display} now</span>
      <span class={["text-sm font-semibold tabular-nums", tone_text(@selected_card.tone)]}>
        {@selected_card.arrow} {@selected_card.delta_abs} since start
      </span>
    </div>

    <div class="w-full">{@chart}</div>

    <div class="flex gap-4 flex-wrap mt-2 text-xs text-parchment-dim">
      <span :if={:intake in @legend} class="inline-flex items-center gap-1.5">
        <span class="w-2.5 h-2.5 rounded-full" style="background:#45C4AE"></span>intake
      </span>
      <span :if={:visit in @legend} class="inline-flex items-center gap-1.5">
        <span class="w-2.5 h-2.5 rounded-full" style="background:#211D16;border:1.5px solid #45C4AE"></span>visit
      </span>
      <span :if={:goal in @legend} class="inline-flex items-center gap-1.5">
        <span class="inline-block w-4" style="border-top:2px dashed #E8622C"></span>goal
      </span>
      <span :if={:band in @legend} class="inline-flex items-center gap-1.5">
        <span class="inline-block w-3.5 h-2.5 rounded-sm" style="background:rgba(69,196,174,0.18)"></span>healthy range
      </span>
    </div>
    """
  end

  defp tone_text(:good), do: "text-basil"
  defp tone_text(:bad), do: "text-error-500"
  defp tone_text(_), do: "text-parchment-dim"
end
