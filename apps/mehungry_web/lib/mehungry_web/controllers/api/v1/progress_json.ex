defmodule MehungryWeb.Api.V1.ProgressJSON do
  @moduledoc """
  Serializers for the self-tracking progress journal (spec §19,
  `/api/v1/me/progress/*`). Distinct from `NutritionistJSON.progress/2`
  (spec §18 `GET /me/progress` — the flat nutritionist-recorded history),
  which stays untouched.

  History points reuse the §18 point shape (`date`/`source` + the six metric
  keys); self-logged points carry `source: "self"`. Metric labels/units come
  from `MehungryWeb.MeasurementChart` so they localize with the request and
  can never drift from the web chart.
  """

  alias Mehungry.Progress.{Entry, Period, Photo}
  alias MehungryWeb.MeasurementChart

  @metric_keys ~w(weight_kg body_fat_percentage waist_cm muscle_mass_kg bmi bmr_kcal)

  def period(%Period{} = period) do
    %{
      id: period.id,
      kind: period.kind,
      professional_id: period.professional_id,
      started_on: Date.to_iso8601(period.started_on),
      ended_on: period.ended_on && Date.to_iso8601(period.ended_on),
      active: is_nil(period.ended_on),
      self_logging: period.kind == "self" and is_nil(period.ended_on),
      tracked_metrics: period.tracked_metrics,
      goals: period.goals || %{},
      shared_with_nutritionist: period.shared_with_nutritionist,
      title: period.title,
      notes: period.notes,
      height_m: period.height_m,
      sex: period.sex,
      age: period.age
    }
  end

  @doc "Full period payload: the period + everything its dashboard screen needs."
  def period_detail(%Period{} = p, history, context, comparison, photo_markers) do
    period(p)
    |> Map.merge(%{
      metrics: Enum.map(@metric_keys, &metric_meta/1),
      context: context_json(context),
      history: Enum.map(history, &point/1),
      comparison: comparison_json(comparison),
      photo_markers: Enum.map(photo_markers, &marker/1)
    })
  end

  def entry(%Entry{} = entry) do
    %{
      id: entry.id,
      period_id: entry.progress_period_id,
      entry_date: Date.to_iso8601(entry.entry_date),
      weight_kg: entry.weight_kg,
      waist_cm: entry.waist_cm,
      body_fat_percentage: entry.body_fat_percentage,
      muscle_mass_kg: entry.muscle_mass_kg,
      bmi: entry.bmi,
      bmr_kcal: entry.bmr_kcal,
      note: entry.note,
      photos: entry.photos |> loaded() |> Enum.map(&photo/1)
    }
  end

  def photo(%Photo{} = photo) do
    %{id: photo.id, url: photo.url, caption: photo.caption, position: photo.position}
  end

  # ── internals ────────────────────────────────────────────────────────────────

  defp metric_meta(key) do
    %{
      key: key,
      label: MeasurementChart.metric_label(key),
      unit: MeasurementChart.metric_unit(key)
    }
  end

  defp context_json(context) do
    %{
      height_m: context[:height_m],
      sex: context[:sex],
      ideal_weight_kg: context[:ideal_weight_kg],
      goals: context[:goals] || %{}
    }
  end

  defp point(point) do
    base = %{date: Date.to_iso8601(point.date), source: to_string(point.source)}

    Enum.reduce(@metric_keys, base, fn key, acc ->
      Map.put(acc, key, Map.get(point, String.to_existing_atom(key)))
    end)
  end

  defp comparison_json(nil), do: nil

  defp comparison_json(%{before: before_side, now: now_side}) do
    %{before: side(before_side), now: side(now_side)}
  end

  defp side(%{date: date, url: url, entry: entry}) do
    %{date: Date.to_iso8601(date), url: url, entry: entry |> no_photos_entry()}
  end

  # The comparison sides embed their entry's measurements but not the photo
  # list (the side's `url` is the photo) — keeps the payload flat.
  defp no_photos_entry(entry) do
    %{
      id: entry.id,
      entry_date: Date.to_iso8601(entry.entry_date),
      weight_kg: entry.weight_kg,
      waist_cm: entry.waist_cm,
      body_fat_percentage: entry.body_fat_percentage,
      muscle_mass_kg: entry.muscle_mass_kg,
      bmi: entry.bmi,
      bmr_kcal: entry.bmr_kcal
    }
  end

  defp marker(m) do
    %{date: Date.to_iso8601(m.date), url: m.url, entry_id: m.entry_id, caption: m.caption}
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []
end
