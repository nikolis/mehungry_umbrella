defmodule MehungryWeb.ProgressOverlayChartIndexed do
  @moduledoc """
  **Prototype** — the index-to-baseline alternative to
  `MehungryWeb.ProgressOverlayChart.overlay_svg/3`.

  Instead of min–max normalizing each series to its own invisible range (which
  makes heights incomparable across lines, amplifies noise, and collapses flat
  series to a meaningless mid-plot), every series is expressed as a **percentage
  of its own first reading** (`first = 100%`). That gives one **shared,
  labelled** y-axis: "+8%" means the same thing for weight and protein, so lines
  can legitimately be compared, a `100%` baseline reference line reads as "no
  change", and a genuinely flat series sits honestly *on* the baseline.

  Drop-in: same `(specs, selected, bounds)` signature and the same spec shape as
  `ProgressOverlayChart.series_specs/2` produces (`%{key,label,unit,color,points,
  latest}`), so the host keeps using that module for `series_specs/2`,
  `sanitize_selection/2`, `axis/3`, `legend_entries/2`, and the toggle/legend
  components — only the chart SVG call is swapped.

  Caveat: a series whose **first point is ≤ 0** can't be indexed multiplicatively
  (no "% change from zero"), so it is silently omitted from the plot. This is rare
  — only a nutrition series whose very first logged day was literally zero of that
  nutrient — and body metrics (kg/%/cm/kcal) are always positive.

  Secondary encoding (dataviz): body series draw **solid**, nutrition series
  **dashed**, so the two kinds stay distinguishable even where two hues collide
  under colour-vision deficiency (the categorical palette clears adjacent CVD but,
  like any >8-hue set, not every arbitrary pair). Direct end-labels (≤ 4 series)
  and per-point `<title>` tooltips name each line.
  """

  import Phoenix.HTML, only: [raw: 1]

  # ── design tokens (dark `ink-panel` surface) ───────────────────────────────────
  @c_grid "#332e20"
  @c_dim "#A9A08C"
  @c_panel "#211D16"
  # the 100%-baseline reference line: brighter than the grid, dimmer than data
  @c_baseline "#6B6350"

  # ── geometry — MUST equal MeasurementChart's (photo_strip alignment) ───────────
  @w 680
  @h 280
  @ml 52
  @mr 20
  @mt 24
  @mb 44

  @doc """
  The indexed-to-baseline overlay as a `raw/1`-wrapped SVG, or `nil` when no
  selected series is plottable (none selected, or every selected series has a
  non-positive baseline). Drop-in for `ProgressOverlayChart.overlay_svg/3`.
  `bounds` widens the date axis to the viewed period, exactly as
  `ProgressOverlayChart.axis/3`.
  """
  def overlay_svg(specs, selected, bounds \\ nil) do
    active =
      specs
      |> Enum.filter(&MapSet.member?(selected, &1.key))
      |> Enum.filter(&positive_baseline?/1)

    case active do
      [] -> nil
      active -> build_overlay(active, bounds)
    end
  end

  defp positive_baseline?(%{points: points}) do
    match?(%{value: v} when v > 0, List.first(points))
  end

  defp build_overlay(active, bounds) do
    plot_w = @w - @ml - @mr
    plot_h = @h - @mt - @mb

    {min_d, max_d} = date_bounds(active, bounds)
    span = Date.diff(max_d, min_d)

    x_of = fn d ->
      if span == 0, do: @ml + plot_w / 2, else: @ml + Date.diff(d, min_d) / span * plot_w
    end

    # Index every point to its series' first reading = 100%.
    indexed =
      Enum.map(active, fn s ->
        first = List.first(s.points).value

        ipoints =
          Enum.map(s.points, fn p ->
            %{date: p.date, idx: 100.0 * p.value / first, raw: p.value}
          end)

        Map.put(s, :ipoints, ipoints)
      end)

    # Shared y-range over every indexed value, always including the 100% baseline.
    all_idx = [100.0 | for(s <- indexed, p <- s.ipoints, do: p.idx)]
    {lo, hi} = Enum.min_max(all_idx)
    pad = max(hi - lo, 1.0) * 0.08
    y_lo = lo - pad
    y_hi = hi + pad

    y_of = fn v -> @mt + plot_h * (y_hi - v) / (y_hi - y_lo) end

    # Direct end-labels only while the plot stays legible (≤ 4 lines).
    direct = length(indexed) <= 4
    title = Enum.map_join(indexed, ", ", & &1.label)

    svg =
      ~s(<svg viewBox="0 0 #{@w} #{@h}" class="w-full h-auto block" font-family="ui-sans-serif, system-ui, sans-serif" role="img" aria-label="#{esc(title)}, indexed to each series' first reading">) <>
        gridlines_svg(plot_w, y_lo, y_hi, y_of) <>
        baseline_svg(plot_w, y_of) <>
        Enum.map_join(indexed, &series_svg(&1, x_of, y_of, direct)) <>
        x_labels_svg(min_d, max_d, span, x_of) <>
        y_title_svg(plot_h) <>
        "</svg>"

    raw(svg)
  end

  # ── axis / grid ────────────────────────────────────────────────────────────────

  # 5 horizontal gridlines, now carrying real, shared percentage values.
  defp gridlines_svg(plot_w, y_lo, y_hi, y_of) do
    Enum.map_join(0..4, fn t ->
      v = y_hi - (y_hi - y_lo) * t / 4
      y = y_of.(v)

      ~s(<line x1="#{@ml}" y1="#{f(y)}" x2="#{@ml + plot_w}" y2="#{f(y)}" stroke="#{@c_grid}" stroke-width="1"/>) <>
        ~s(<text x="#{@ml - 8}" y="#{f(y + 3.5)}" text-anchor="end" fill="#{@c_dim}" font-size="11">#{round(v)}%</text>)
    end)
  end

  # The 100% reference line — "no change since the first reading".
  defp baseline_svg(plot_w, y_of) do
    y = y_of.(100.0)

    ~s(<line x1="#{@ml}" y1="#{f(y)}" x2="#{@ml + plot_w}" y2="#{f(y)}" stroke="#{@c_baseline}" stroke-width="1.25" stroke-dasharray="4 4"/>) <>
      ~s(<text x="#{@ml + plot_w}" y="#{f(y - 5)}" text-anchor="end" fill="#{@c_baseline}" font-size="10">baseline</text>)
  end

  # ── series ───────────────────────────────────────────────────────────────────

  defp series_svg(s, x_of, y_of, direct) do
    color = s.color
    # Secondary encoding: nutrition dashed, body solid (see moduledoc).
    dash = if s.kind == :nutrition, do: ~s( stroke-dasharray="6 3"), else: ""

    coords =
      Enum.map(s.ipoints, fn p -> {x_of.(p.date), y_of.(p.idx), p} end)

    line_d =
      coords
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{x, y, _p}, i} ->
        "#{if i == 0, do: "M", else: "L"}#{f(x)} #{f(y)}"
      end)

    last_i = length(coords) - 1

    dots =
      coords
      |> Enum.with_index()
      |> Enum.map_join(fn {{x, y, p}, i} ->
        tip = tooltip(s, p)

        if i == last_i do
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="7" fill="#{color}" opacity="0.18"/>) <>
            ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="4" fill="#{color}" stroke="#{@c_panel}" stroke-width="1.5">#{tip}</circle>)
        else
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="2.6" fill="#{color}">#{tip}</circle>)
        end
      end)

    end_label =
      if direct do
        {x, y, _p} = List.last(coords)

        ~s(<text x="#{f(x - 6)}" y="#{f(y - 9)}" text-anchor="end" fill="#{color}" font-size="10.5" font-weight="600">#{esc(s.label)}</text>)
      else
        ""
      end

    ~s(<path d="#{line_d}" fill="none" stroke="#{color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"#{dash}/>) <>
      dots <> end_label
  end

  # Native-tooltip recovery of the absolute value the index hides.
  defp tooltip(s, p) do
    pct = p.idx - 100.0
    sign = if pct >= 0, do: "+", else: ""
    delta = fmt_num(Float.round(pct, 1))

    "<title>#{esc(s.label)} · #{Calendar.strftime(p.date, "%b %d, %Y")} · #{fmt_num(p.raw)}#{maybe_unit(s.unit)} (#{sign}#{delta}%)</title>"
  end

  # ~6 evenly spaced rotated date ticks over the union span.
  defp x_labels_svg(min_d, max_d, span, x_of) do
    y = @h - @mb + 16
    ticks = min(span, 6)

    0..ticks//1
    |> Enum.map(fn t ->
      if t == ticks, do: max_d, else: Date.add(min_d, div(span * t, max(ticks, 1)))
    end)
    |> Enum.uniq()
    |> Enum.map_join(fn d ->
      x = x_of.(d)

      ~s|<text x="#{f(x)}" y="#{y}" text-anchor="end" fill="#{@c_dim}" font-size="10.5" transform="rotate(-32 #{f(x)} #{y})">#{Calendar.strftime(d, "%b %d")}</text>|
    end)
  end

  defp y_title_svg(plot_h) do
    cy = @mt + plot_h / 2

    ~s|<text x="14" y="#{f(cy)}" text-anchor="middle" fill="#{@c_dim}" font-size="11" transform="rotate(-90 14 #{f(cy)})">% of first reading</text>|
  end

  # ── shared date helpers (mirror ProgressOverlayChart) ──────────────────────────

  defp date_bounds(active, bounds) do
    dates = for s <- active, p <- s.points, do: p.date
    min_max_dates(dates ++ bound_dates(bounds))
  end

  defp bound_dates(nil), do: []
  defp bound_dates({lo, hi}), do: Enum.reject([lo, hi], &is_nil/1)

  defp min_max_dates(dates), do: {Enum.min(dates, Date), Enum.max(dates, Date)}

  # ── tiny formatters ──────────────────────────────────────────────────────────

  defp esc(s), do: s |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp maybe_unit(nil), do: ""
  defp maybe_unit(""), do: ""
  defp maybe_unit(u), do: " " <> u

  defp fmt_num(v) when is_integer(v), do: Integer.to_string(v)

  defp fmt_num(v) when is_float(v) do
    r = Float.round(v, 1)

    if r == Float.round(r, 0),
      do: Integer.to_string(trunc(r)),
      else: :erlang.float_to_binary(r, decimals: 1)
  end

  defp f(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)
end
