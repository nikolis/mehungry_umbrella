defmodule Mehungry.Professionals.Anthropometrics do
  @moduledoc """
  Pure anthropometric / energy-expenditure calculator for a `ClientIntake`.

  No Ecto, no side effects — just the formulas a nutritionist applies at every
  intake, plus the `<select>` vocabularies that drive them (so the forms and the
  math share one source of truth):

    * **BMI** = `weight_kg / height_m²`
    * **BMR** (basal metabolic rate) via Mifflin–St Jeor
    * **TDEE** (total daily energy expenditure) = `BMR × activity factor`

  Every function returns `nil` when its inputs are missing or out of range, so
  callers can fill only what they can compute.
  """

  @sexes [{"male", "Male"}, {"female", "Female"}]

  # {value, label, activity factor}
  @activity_levels [
    {"sedentary", "Sedentary (little/no exercise)", 1.2},
    {"light", "Lightly active (1–3 days/wk)", 1.375},
    {"moderate", "Moderately active (3–5 days/wk)", 1.55},
    {"active", "Active (6–7 days/wk)", 1.725},
    {"very_active", "Very active (hard exercise/physical job)", 1.9}
  ]

  @doc "Allowed `sex` values with display labels, for the picker and validation."
  def sexes, do: @sexes

  @doc "Allowed `activity_level` values with labels + factors, for the picker and validation."
  def activity_levels, do: @activity_levels

  @doc "Valid `sex` string values."
  def sex_values, do: Enum.map(@sexes, &elem(&1, 0))

  @doc "Valid `activity_level` string values."
  def activity_values, do: Enum.map(@activity_levels, &elem(&1, 0))

  @doc "Display label for a stored `activity_level` value (`nil` → `nil`)."
  def activity_label(level) do
    Enum.find_value(@activity_levels, fn {value, label, _f} ->
      if value == level, do: label
    end)
  end

  @doc "Display label for a stored `sex` value (`nil` → `nil`)."
  def sex_label(sex) do
    Enum.find_value(@sexes, fn {value, label} -> if value == sex, do: label end)
  end

  @doc """
  Body Mass Index from height (m) and weight (kg), rounded to 1 dp.
  `nil` if either input is missing or non-positive.
  """
  def bmi(height_m, weight_kg)
      when is_number(height_m) and is_number(weight_kg) and height_m > 0 and weight_kg > 0 do
    Float.round(weight_kg / (height_m * height_m), 1)
  end

  def bmi(_, _), do: nil

  @doc """
  Basal metabolic rate (kcal/day) via Mifflin–St Jeor, rounded to a whole kcal.

      10 * kg + 6.25 * cm − 5 * age + (5 for male | −161 for female)

  `nil` unless sex is `"male"`/`"female"` and age/height/weight are positive.
  """
  def bmr_kcal(sex, age, height_m, weight_kg)
      when sex in ["male", "female"] and is_number(age) and is_number(height_m) and
             is_number(weight_kg) and age > 0 and height_m > 0 and weight_kg > 0 do
    base = 10 * weight_kg + 6.25 * (height_m * 100) - 5 * age
    adjusted = base + sex_offset(sex)
    round(adjusted)
  end

  def bmr_kcal(_, _, _, _), do: nil

  @doc """
  Total daily energy expenditure (kcal/day) = `bmr × activity factor`, rounded.
  `nil` if `bmr` is missing or the activity level is unknown.
  """
  def tdee_kcal(bmr, activity_level) when is_number(bmr) do
    case activity_factor(activity_level) do
      nil -> nil
      factor -> round(bmr * factor)
    end
  end

  def tdee_kcal(_, _), do: nil

  @doc """
  Derive `%{bmi:, bmr_kcal:, tdee_kcal:}` from an input map, including **only**
  the keys it could actually compute. Accepts string or atom keys for
  `height_m`, `weight_kg`, `sex`, `age`, `activity_level`.
  """
  def compute(attrs) when is_map(attrs) do
    height_m = numeric(fetch(attrs, :height_m))
    weight_kg = numeric(fetch(attrs, :weight_kg))
    sex = fetch(attrs, :sex)
    age = numeric(fetch(attrs, :age))
    activity = fetch(attrs, :activity_level)

    bmi = bmi(height_m, weight_kg)
    bmr = bmr_kcal(sex, age, height_m, weight_kg)
    tdee = tdee_kcal(bmr, activity)

    %{bmi: bmi, bmr_kcal: bmr, tdee_kcal: tdee}
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp sex_offset("male"), do: 5
  defp sex_offset("female"), do: -161

  defp activity_factor(level) do
    Enum.find_value(@activity_levels, fn {value, _label, factor} ->
      if value == level, do: factor
    end)
  end

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  # Accepts numbers or parseable strings (form params arrive as strings); blank/garbage → nil.
  defp numeric(n) when is_number(n), do: n

  defp numeric(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp numeric(_), do: nil
end
