defmodule MehungryWeb.MeasurementChart do
  @moduledoc """
  Shared helpers for the client body-measurement progress chart, used by both the
  nutritionist client file (`ClientDetail`) and the client's own profile
  (`ProfileLive`).

  A measurement history is `[%{date: ~D[...], source:, <metric> => number | nil}]`
  as returned by `Mehungry.Professionals.measurement_history/1`. Each metric has
  its own unit, so the UI charts **one metric at a time** (a shared y-axis across
  kg / % / cm / kcal would mislead) — these helpers pick the metric and build a
  single-series VegaLite line+point spec matching the app's dark chart styling.
  """

  alias VegaLite, as: Vl

  # metric key => {label, unit | nil}. Order is the selector display order.
  @metrics [
    {"weight_kg", {"Weight", "kg"}},
    {"body_fat_percentage", {"Body fat", "%"}},
    {"waist_cm", {"Waist", "cm"}},
    {"muscle_mass_kg", {"Muscle mass", "kg"}},
    {"bmi", {"BMI", nil}},
    {"bmr_kcal", {"BMR", "kcal"}}
  ]

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
      count = Enum.count(history, fn point -> point[String.to_existing_atom(key)] end)
      count >= 2
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

  @doc """
  A single-series VegaLite spec (as a plain map via `Vl.to_spec/1`) plotting
  `metric` over time from `history`. Returns `nil` when `metric` is nil.
  """
  def build_spec(_history, nil, _width), do: nil

  def build_spec(history, metric, width) do
    key = String.to_existing_atom(metric)
    unit = metric_unit(metric)
    y_title = if unit, do: "#{metric_label(metric)} (#{unit})", else: metric_label(metric)

    chart_data =
      history
      |> Enum.filter(&(&1[key] && &1.date))
      |> Enum.map(&%{"date" => to_string(&1.date), "value" => &1[key]})

    Vl.new(width: width, height: 200, autosize: [type: "fit", contains: "padding"])
    |> Vl.data_from_values(chart_data)
    |> Vl.mark(:line, color: "#10B981", point: [color: "#10B981", filled: true])
    |> Vl.encode_field(:x, "date",
      type: :temporal,
      axis: [
        label_angle: -35,
        title: nil,
        label_color: "#94A3B8",
        domain_color: "#334155",
        tick_color: "#334155"
      ]
    )
    |> Vl.encode_field(:y, "value",
      type: :quantitative,
      scale: [zero: false],
      axis: [
        title: y_title,
        label_color: "#94A3B8",
        domain_color: "#334155",
        grid_color: "#1E293B"
      ]
    )
    |> Vl.encode(:tooltip, [
      [field: "date", type: :temporal, title: "Date"],
      [field: "value", type: :quantitative, title: y_title]
    ])
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end
end
