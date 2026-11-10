defmodule MehungryWeb.ProgressOverlayChart do
  @moduledoc """
  The profile progress tab's **multi-series overlay chart**: body measurements
  (`MehungryWeb.MeasurementChart`'s history shape) and per-day nutrition-intake
  series (`Mehungry.History.daily_nutrition_history/3`) plotted together on one
  hand-built SVG.

  The series span incompatible units (kg / % / cm / kcal / g), so each series is
  **min–max normalized to its own range** — the plot compares *trends*, not
  magnitudes. The y-axis therefore carries no numbers; each series' latest
  absolute value lives in the legend instead. The one exception: with exactly
  **one** series selected the gridlines are labelled with that series' real
  values (restoring the old single-metric chart's readability).

  Geometry constants are copied **verbatim** from `MeasurementChart` — its
  `photo_strip/1` pins photo thumbnails to this chart's date axis via the same
  margin math, so the two modules must never drift (see the mirror comment
  there).

  Stateless like `MeasurementChart`: the host LiveView owns the selection (a
  `MapSet` of series keys) and handles the `toggle_series` event the toggle
  buttons emit.
  """

  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  use Gettext, backend: MehungryWeb.Gettext

  alias MehungryWeb.MeasurementChart

  # ── design tokens (always on the dark `ink-panel` surface) ─────────────────────
  @c_grid "#332e20"
  @c_dim "#A9A08C"
  @c_panel "#211D16"

  # ── chart geometry — MUST equal MeasurementChart's (photo_strip alignment) ─────
  @w 680
  @h 280
  @ml 52
  @mr 20
  @mt 24
  @mb 44

  # Nutrition series: {key, label, unit, field in daily_nutrition_history/3 rows}.
  # String keys so phx-value round-trips; display order mirrors the feature spec.
  @nutrition_series [
    {"nutrition_total_fat_g", "Total Fat", "g", :total_fat_g},
    {"nutrition_polyunsaturated_fat_g", "Polyunsaturated Fat", "g", :polyunsaturated_fat_g},
    {"nutrition_monounsaturated_fat_g", "Monounsaturated Fat", "g", :monounsaturated_fat_g},
    {"nutrition_trans_fat_g", "Trans Fat", "g", :trans_fat_g},
    {"nutrition_carbs_g", "Carbohydrates", "g", :carbs_g},
    {"nutrition_sugars_g", "Sugars", "g", :sugars_g},
    {"nutrition_fiber_g", "Fiber", "g", :fiber_g},
    {"nutrition_protein_g", "Protein", "g", :protein_g},
    {"nutrition_energy_kcal", "Energy", "kcal", :energy_kcal}
  ]

  # Fixed per-key categorical palette (body metrics then nutrition, catalog
  # order), extending the 8 muted-on-ink colors of `CalendarLive.PieChart`.
  # Fixed assignment keeps a series' color stable whatever else is toggled.
  @palette [
    # body: weight, body fat, waist, muscle mass, bmi, bmr
    "#E8622C",
    "#45C4AE",
    "#E7B54A",
    "#C77DAD",
    "#8FB46B",
    "#6FA1C9",
    # nutrition: total fat, poly, mono, trans, carbs, sugars, fiber, protein, energy
    "#D98299",
    "#7FB8A0",
    "#B0A1D6",
    "#C98D6B",
    "#9AB8D9",
    "#D6C08A",
    "#86C3B5",
    "#DA9E66",
    "#B7C96B"
  ]

  # key => history-field atom for the body metrics, resolved at compile time
  # (runtime to_existing_atom would depend on schema-module load order).
  @body_fields Map.new(
                 MehungryWeb.MeasurementChart.metric_keys(),
                 &{&1, String.to_atom(&1)}
               )

  @doc "The nutrition series keys in display order."
  def nutrition_keys, do: Enum.map(@nutrition_series, &elem(&1, 0))

  # Body labels are translated by MeasurementChart; nutrition labels here. All
  # label literals are compile-time, so gettext is applied at runtime.
  defp translate_label("Total Fat"), do: gettext("Total Fat")
  defp translate_label("Polyunsaturated Fat"), do: gettext("Polyunsaturated Fat")
  defp translate_label("Monounsaturated Fat"), do: gettext("Monounsaturated Fat")
  defp translate_label("Trans Fat"), do: gettext("Trans Fat")
  defp translate_label("Carbohydrates"), do: gettext("Carbohydrates")
  defp translate_label("Sugars"), do: gettext("Sugars")
  defp translate_label("Fiber"), do: gettext("Fiber")
  defp translate_label("Protein"), do: gettext("Protein")
  defp translate_label("Energy"), do: gettext("Energy")
  defp translate_label(other), do: other

  # ── series specs ───────────────────────────────────────────────────────────────

  @doc """
  One plottable spec per series with **≥ 2 dated points** — body metrics first
  (from the measurement `history`), then nutrition series (from
  `daily_nutrition_history/3` rows). Each spec:

      %{key, label, unit, color, kind: :body | :nutrition,
        points: [%{date: Date.t(), value: float}],   # ascending
        latest: "79 kg"}
  """
  def series_specs(measurement_history, nutrition_history) do
    body =
      MeasurementChart.metric_keys()
      |> Enum.map(fn key ->
        points = body_points(measurement_history, key)

        spec(key, MeasurementChart.metric_label(key), MeasurementChart.metric_unit(key),
          kind: :body,
          points: points
        )
      end)

    nutrition =
      Enum.map(@nutrition_series, fn {key, label, unit, field} ->
        points =
          nutrition_history
          |> Enum.filter(&is_number(&1[field]))
          |> Enum.map(&%{date: &1.date, value: &1[field] * 1.0})

        spec(key, translate_label(label), unit, kind: :nutrition, points: points)
      end)

    (body ++ nutrition)
    |> Enum.filter(&(length(&1.points) >= 2))
  end

  defp spec(key, label, unit, kind: kind, points: points) do
    latest =
      case List.last(points) do
        %{value: v} -> fmt_num(v) <> maybe_unit(unit)
        nil -> nil
      end

    %{
      key: key,
      label: label,
      unit: unit,
      color: series_color(key),
      kind: kind,
      points: points,
      latest: latest
    }
  end

  # Same filter/sort as MeasurementChart.present_points/2 — source dropped: the
  # overlay colors by series, not by who recorded the point.
  defp body_points(history, key) do
    atom = Map.fetch!(@body_fields, key)

    history
    |> Enum.filter(&(&1[atom] && &1.date))
    |> Enum.map(&%{date: &1.date, value: &1[atom] * 1.0})
    |> Enum.sort_by(& &1.date, Date)
  end

  defp series_color(key) do
    keys = MeasurementChart.metric_keys() ++ nutrition_keys()

    case Enum.find_index(keys, &(&1 == key)) do
      nil -> @c_dim
      i -> Enum.at(@palette, rem(i, length(@palette)))
    end
  end

  @doc """
  The selection to actually chart: `selected` pruned to the available spec keys,
  defaulting to the first body series (else the first spec) when nothing valid
  remains. Called on (re)load — toggling everything off mid-session is still
  possible because the `toggle_series` handler assigns its MapSet directly.
  """
  def sanitize_selection(nil, specs), do: default_selection(specs)

  def sanitize_selection(%MapSet{} = selected, specs) do
    available = MapSet.new(specs, & &1.key)
    kept = MapSet.intersection(selected, available)

    if MapSet.size(kept) > 0, do: kept, else: default_selection(specs)
  end

  defp default_selection(specs) do
    case Enum.find(specs, &(&1.kind == :body)) || List.first(specs) do
      nil -> MapSet.new()
      spec -> MapSet.new([spec.key])
    end
  end

  @doc """
  The `{min_date, max_date}` union over the **selected** specs' points — the date
  axis the chart draws, which `MeasurementChart.photo_strip/1` also pins to.
  `nil` when nothing is selected.

  `bounds` (`{Date | nil, Date | nil}`) widens the axis to the viewed period's
  own range so the diagram always spans the whole period, not just the dates
  that happen to carry data. It only ever *extends*: nutritionist-aligned
  periods chart measurement history from before `started_on`, and those points
  must stay on-plot.
  """
  def axis(specs, selected, bounds \\ nil) do
    dates =
      for s <- specs, MapSet.member?(selected, s.key), p <- s.points, do: p.date

    case dates do
      [] -> nil
      dates -> dates |> Kernel.++(bound_dates(bounds)) |> min_max_dates()
    end
  end

  defp bound_dates(nil), do: []
  defp bound_dates({lo, hi}), do: Enum.reject([lo, hi], &is_nil/1)

  defp min_max_dates(dates), do: {Enum.min(dates, Date), Enum.max(dates, Date)}

  # ── the overlay SVG ────────────────────────────────────────────────────────────

  @doc """
  The normalized multi-series trend SVG (`raw/1`-wrapped), or `nil` when no
  selected series. Each series min–max normalized to its own range (flat series
  sit mid-plot); lines bridge date gaps; the latest point of each series is
  emphasized. With exactly one series selected the gridlines carry that series'
  real values and a rotated y-title names it. `bounds` widens the date axis to
  the viewed period's range, exactly as in `axis/3`.
  """
  def overlay_svg(specs, selected, bounds \\ nil) do
    active = Enum.filter(specs, &MapSet.member?(selected, &1.key))

    case active do
      [] -> nil
      active -> build_overlay(active, bounds)
    end
  end

  defp build_overlay(active, bounds) do
    plot_w = @w - @ml - @mr
    plot_h = @h - @mt - @mb

    {min_d, max_d} = date_bounds(active, bounds)
    span = Date.diff(max_d, min_d)

    x_of = fn d ->
      if span == 0, do: @ml + plot_w / 2, else: @ml + Date.diff(d, min_d) / span * plot_w
    end

    # 6% inner padding keeps lines off the plot edges.
    norm_y = fn frac -> @mt + plot_h * (0.06 + (1.0 - frac) * 0.88) end

    single = match?([_], active)

    labels =
      case active do
        [only] -> single_axis_labels(only, norm_y)
        _ -> ""
      end

    title = Enum.map_join(active, ", ", & &1.label)

    svg =
      ~s(<svg viewBox="0 0 #{@w} #{@h}" class="w-full h-auto block" font-family="ui-sans-serif, system-ui, sans-serif" role="img" aria-label="#{Phoenix.HTML.html_escape(title) |> Phoenix.HTML.safe_to_string()} over time">) <>
        gridlines_svg(plot_w) <>
        labels <>
        Enum.map_join(active, &series_svg(&1, x_of, norm_y)) <>
        x_labels_svg(min_d, max_d, span, x_of) <>
        if(single, do: y_title_svg(hd(active), plot_h), else: "") <>
        "</svg>"

    raw(svg)
  end

  # Data dates widened by the period bounds — must match `axis/3`, or the photo
  # strip pins thumbnails to a different date axis than the plot draws.
  defp date_bounds(active, bounds) do
    dates = for s <- active, p <- s.points, do: p.date
    min_max_dates(dates ++ bound_dates(bounds))
  end

  # Unlabelled horizontal gridlines — normalized axes carry no shared numbers.
  defp gridlines_svg(plot_w) do
    Enum.map_join(0..4, fn t ->
      y = @mt + (@h - @mt - @mb) * t / 4

      ~s(<line x1="#{@ml}" y1="#{f(y)}" x2="#{@ml + plot_w}" y2="#{f(y)}" stroke="#{@c_grid}" stroke-width="1"/>)
    end)
  end

  # Single-series mode: label the normalized gridlines with the series' real
  # values. Gridline t sits at normalized fraction (1 - t/4) inside the padded
  # band, so invert norm_y's padding to recover the value it represents.
  defp single_axis_labels(%{points: points}, norm_y) do
    {lo, hi} = points |> Enum.map(& &1.value) |> Enum.min_max()
    range = hi - lo

    Enum.map_join(0..4, fn t ->
      frac = 1.0 - t / 4
      v = lo + range * frac
      y = norm_y.(frac)

      ~s(<text x="#{@ml - 8}" y="#{f(y + 3.5)}" text-anchor="end" fill="#{@c_dim}" font-size="11">#{fmt_num(Float.round(v * 1.0, 1))}</text>)
    end)
  end

  defp series_svg(%{points: points, color: color}, x_of, norm_y) do
    {lo, hi} = points |> Enum.map(& &1.value) |> Enum.min_max()
    range = hi - lo

    coords =
      Enum.map(points, fn p ->
        frac = if range == 0, do: 0.5, else: (p.value - lo) / range
        {x_of.(p.date), norm_y.(frac)}
      end)

    line_d =
      coords
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{x, y}, i} ->
        "#{if i == 0, do: "M", else: "L"}#{f(x)} #{f(y)}"
      end)

    dots =
      coords
      |> Enum.with_index()
      |> Enum.map_join(fn {{x, y}, i} ->
        if i == length(coords) - 1 do
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="7" fill="#{color}" opacity="0.18"/>) <>
            ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="4" fill="#{color}" stroke="#{@c_panel}" stroke-width="1.5"/>)
        else
          ~s(<circle cx="#{f(x)}" cy="#{f(y)}" r="2.6" fill="#{color}"/>)
        end
      end)

    ~s(<path d="#{line_d}" fill="none" stroke="#{color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>) <>
      dots
  end

  # ~6 evenly spaced rotated date ticks over the union span (point dates differ
  # per series, so ticks are span-based rather than point-based).
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

  defp y_title_svg(%{label: label, unit: unit}, plot_h) do
    title = if unit, do: "#{label} (#{unit})", else: label
    cy = @mt + plot_h / 2

    ~s|<text x="14" y="#{f(cy)}" text-anchor="middle" fill="#{@c_dim}" font-size="11" transform="rotate(-90 14 #{f(cy)})">#{Phoenix.HTML.html_escape(title) |> Phoenix.HTML.safe_to_string()}</text>|
  end

  @doc """
  Legend entries for the selected specs: `%{key, label, color, latest}` — the
  latest absolute value is the normalized plot's substitute for y-axis numbers.
  """
  def legend_entries(specs, selected) do
    specs
    |> Enum.filter(&MapSet.member?(selected, &1.key))
    |> Enum.map(&Map.take(&1, [:key, :label, :color, :latest]))
  end

  # ── components ─────────────────────────────────────────────────────────────────

  @doc "The chart legend: one swatch + label + latest-value chip per plotted series."
  attr :legend, :list, required: true

  def overlay_legend(assigns) do
    ~H"""
    <div :if={@legend != []} class="flex gap-x-4 gap-y-1 flex-wrap mt-2 text-xs text-parchment-dim">
      <span :for={l <- @legend} class="inline-flex items-center gap-1.5">
        <span class="w-2.5 h-2.5 rounded-full shrink-0" style={"background:#{l.color}"}></span>
        <span>{l.label}</span>
        <span class="text-parchment font-semibold tabular-nums">{l.latest}</span>
      </span>
    </div>
    """
  end

  @doc """
  The series toggles: the body-metric KPI cards (same markup as
  `MeasurementChart.progress_dashboard/1`'s cards, but multi-select) above a
  chip row of nutrition series derived from the user's logged meals. Both emit
  `toggle_series` with the series key; lit state = membership in `selected`.
  """
  attr :cards, :list, required: true
  attr :nutrition_specs, :list, required: true
  attr :selected, :any, required: true

  def series_toggles(assigns) do
    ~H"""
    <div :if={@cards != []} class="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
      <button
        :for={c <- @cards}
        type="button"
        phx-click="toggle_series"
        phx-value-series={c.key}
        aria-pressed={to_string(MapSet.member?(@selected, c.key))}
        class={[
          "text-left rounded-xl p-3 border transition flex flex-col gap-0.5 focus:outline-none focus:ring-2 focus:ring-paprika",
          if(MapSet.member?(@selected, c.key),
            do: "bg-[#2e2112] border-paprika",
            else: "bg-ink-panel2 border-ink-panel2 hover:border-paprika-soft"
          )
        ]}
      >
        <span class="flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full shrink-0" style={"background:#{series_color(c.key)}"}></span>
          <span class={[
            "text-[11px] uppercase tracking-wide font-semibold",
            if(MapSet.member?(@selected, c.key), do: "text-paprika", else: "text-parchment-dim")
          ]}>
            {c.label}
          </span>
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

    <div class="mt-3">
      <div class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim mb-1.5">
        {gettext("From your logged meals")}
      </div>
      <div :if={@nutrition_specs != []} class="flex flex-wrap gap-1.5">
        <button
          :for={s <- @nutrition_specs}
          type="button"
          phx-click="toggle_series"
          phx-value-series={s.key}
          aria-pressed={to_string(MapSet.member?(@selected, s.key))}
          class={[
            "inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs border transition focus:outline-none focus:ring-2 focus:ring-paprika",
            if(MapSet.member?(@selected, s.key),
              do: "bg-[#2e2112] border-paprika text-paprika font-semibold",
              else: "bg-ink-panel2 border-ink-panel2 text-parchment-dim hover:border-paprika-soft"
            )
          ]}
        >
          <span class="w-2 h-2 rounded-full shrink-0" style={"background:#{s.color}"}></span>
          <span>{s.label}</span>
          <span class="text-parchment tabular-nums">{s.latest}</span>
        </button>
      </div>
      <p :if={@nutrition_specs == []} class="text-xs text-parchment-dim">
        {gettext("Log meals on your calendar to overlay nutrition trends here.")}
      </p>
    </div>
    """
  end

  defp tone_text(:good), do: "text-basil"
  defp tone_text(:bad), do: "text-error-500"
  defp tone_text(_), do: "text-parchment-dim"

  # ── tiny shared formatters (private copies of MeasurementChart's) ──────────────

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

  # Format a number as a 1-decimal SVG coordinate string.
  defp f(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)
end
