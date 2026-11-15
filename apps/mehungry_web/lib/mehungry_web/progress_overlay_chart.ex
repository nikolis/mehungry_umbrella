defmodule MehungryWeb.ProgressOverlayChart do
  @moduledoc """
  The profile progress tab's **multi-series overlay** data layer: body
  measurements (`MehungryWeb.MeasurementChart`'s history shape) and per-day
  nutrition-intake series (`Mehungry.History.daily_nutrition_history/3`) combined
  into plottable specs, plus the selection/axis/legend helpers and the toggle +
  legend UI components.

  The SVG itself is drawn by `MehungryWeb.ProgressOverlayChartIndexed`
  (index-to-baseline: every series as a percentage of its own first reading, on a
  shared labelled axis). This module stays rendering-free — it owns the data and
  the fixed per-key categorical palette (`series_color/1`) only.

  Stateless like `MeasurementChart`: the host LiveView owns the selection (a
  `MapSet` of series keys) and handles the `toggle_series` event the toggle
  buttons emit.
  """

  use Phoenix.Component
  use Gettext, backend: MehungryWeb.Gettext

  alias MehungryWeb.MeasurementChart

  # Fallback series colour for an unknown key (on the dark `ink-panel` surface).
  @c_dim "#A9A08C"

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

  # Fixed per-key categorical palette — **one slot per series key**, in
  # `metric_keys/0 ++ nutrition_keys/0` order (9 body, then 9 nutrition = 18).
  # Fixed assignment keeps a series' colour stable whatever else is toggled; a
  # full 18 entries means `series_color/1` never wraps (the old 15-slot list
  # aliased fiber/protein/energy onto weight/body-fat/waist).
  #
  # CVD-validated on the dark `#211D16` surface via the dataviz skill's
  # `validate_palette.js` (paprika `#E8622C` + basil `#45C4AE` are brand tokens,
  # kept fixed):
  #   • chroma floor .......... all 18 PASS (no slot reads gray)
  #   • contrast vs surface ... all 18 PASS (>= 3:1)
  #   • adjacent CVD .......... PASS, worst ΔE 23.9 (was 3.3)
  #   • within-group CVD ...... core-6 body 10.3, nutrition-9 8.4 (floor band) —
  #     legal because every series also carries secondary encoding:
  #     body = solid line, nutrition = dashed (see ProgressOverlayChartIndexed),
  #     plus direct end-labels + legend swatch + hover `<title>`.
  #   • lightness band ........ intentional house-style deviation — the
  #     warm-charcoal system runs marks *lighter* than the validator's dark band,
  #     which is why contrast/chroma still pass (they're never invisible/gray).
  # The circumference metrics (hands/glutes/feet) are the weak tail: niche,
  # body/solid, and when co-plotted their identity is carried by label, not hue.
  @palette [
    # body (metric_keys order): weight, body fat, waist, muscle mass,
    #                           hands, glutes, feet, bmi, bmr
    "#E8622C",
    "#45C4AE",
    "#E7B54A",
    "#C77DAD",
    "#C76A4A",
    "#2FAA98",
    "#B98ACF",
    "#8FB46B",
    "#5E9ED8",
    # nutrition (nutrition_keys order): total fat, poly, mono, trans,
    #                                   carbs, sugars, fiber, protein, energy
    "#E05555",
    "#46B8DC",
    "#E2913C",
    "#5E72D8",
    "#C7D24C",
    "#CE63B0",
    "#2FA66E",
    "#9B8AE0",
    "#C98A52"
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

  # The overlay SVG itself is rendered by `MehungryWeb.ProgressOverlayChartIndexed`
  # (index-to-baseline); this module owns the data (specs/axis/legend) + toggle
  # and legend components only.

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
end
