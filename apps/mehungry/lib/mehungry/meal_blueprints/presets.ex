defmodule Mehungry.MealBlueprints.Presets do
  @moduledoc """
  Ready-made "starter" meal blueprints spanning **sex × activity level × age
  band**, so a new user can instantiate a sensible 7-day target sheet in one
  click instead of authoring 35 meal cards by hand.

  Coverage (36 presets): sex `female | male`, activity
  `no exercise | some exercise | regular exercise`, age bands
  `20s..70s`.

  ## Numbers, and where they come from

  Daily calorie aims follow the USDA/HHS *Estimated Calorie Needs per Day by
  Age, Sex, and Physical Activity Level* table (Dietary Guidelines for
  Americans), using a representative value per decade and mapping
  `no exercise → sedentary`, `some exercise → moderately active`,
  `regular exercise → active`.

  Per-meal targets are a **macro percentage split** (protein / carbs / fats,
  always totalling 100 %) that follows standard energy ratios by activity level:
  protein 20/25/30 %E and carbohydrate 50/48/45 %E for
  `no/some/regular exercise`, with fat taking the remainder (30/27/25 %E). The
  same split is applied to every one of the five calendar meal slots (a ratio,
  not an amount), while the day's `total_calorie_target` carries the absolute aim.

  These are **starting points**, deliberately generic — a user (or their
  nutritionist) is expected to tweak them.

  ## Usage

      # List everything (e.g. to render a picker)
      Mehungry.MealBlueprints.Presets.all()

      # Fetch one descriptor
      preset = Mehungry.MealBlueprints.Presets.get(:female, :regular, 30)

      # Turn it into create_blueprint/1 attrs for a specific user
      attrs = Mehungry.MealBlueprints.Presets.attrs_for(preset, user_id)

      # …or instantiate it straight into that user's account
      {:ok, blueprint} =
        Mehungry.MealBlueprints.Presets.create_for_user(user_id, :male, :some, 40)
  """

  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints

  @sexes [:female, :male]
  @exercise_levels [:none, :some, :regular]
  @age_bands [20, 30, 40, 50, 60, 70]

  # Macro percentage split (protein / carbs / fats, each summing to 100) by
  # activity level. Fat is the remainder after protein + carbs.
  @macro_split %{
    none: %{protein_pct: 20, carbs_pct: 50, fats_pct: 30},
    some: %{protein_pct: 25, carbs_pct: 48, fats_pct: 27},
    regular: %{protein_pct: 30, carbs_pct: 45, fats_pct: 25}
  }

  # USDA estimated daily calorie needs, representative value per decade.
  # Keys: {age_band, exercise_level}.
  @calories %{
    female: %{
      {20, :none} => 2000,
      {20, :some} => 2200,
      {20, :regular} => 2400,
      {30, :none} => 1800,
      {30, :some} => 2000,
      {30, :regular} => 2200,
      {40, :none} => 1800,
      {40, :some} => 2000,
      {40, :regular} => 2200,
      {50, :none} => 1600,
      {50, :some} => 1800,
      {50, :regular} => 2200,
      {60, :none} => 1600,
      {60, :some} => 1800,
      {60, :regular} => 2000,
      {70, :none} => 1600,
      {70, :some} => 1800,
      {70, :regular} => 2000
    },
    male: %{
      {20, :none} => 2400,
      {20, :some} => 2800,
      {20, :regular} => 3000,
      {30, :none} => 2400,
      {30, :some} => 2600,
      {30, :regular} => 3000,
      {40, :none} => 2200,
      {40, :some} => 2600,
      {40, :regular} => 2800,
      {50, :none} => 2200,
      {50, :some} => 2400,
      {50, :regular} => 2800,
      {60, :none} => 2000,
      {60, :some} => 2400,
      {60, :regular} => 2600,
      {70, :none} => 2000,
      {70, :some} => 2200,
      {70, :regular} => 2600
    }
  }

  @doc "All 36 preset descriptors."
  def all do
    for sex <- @sexes, exercise <- @exercise_levels, age <- @age_bands do
      build(sex, exercise, age)
    end
  end

  @doc "The preset descriptor for a `{sex, exercise, age_band}` combination."
  def get(sex, exercise, age_band)
      when sex in @sexes and exercise in @exercise_levels and age_band in @age_bands do
    build(sex, exercise, age_band)
  end

  @doc """
  Full `Mehungry.MealBlueprints.create_blueprint/1` attrs for `user_id` from a
  preset descriptor (or a `{sex, exercise, age_band}` tuple).
  """
  def attrs_for(%{days: _} = preset, user_id) do
    preset
    |> Map.take([
      :name,
      :description,
      :required_nutrients,
      :avoid_nutrients,
      :required_compounds,
      :avoid_compounds,
      :preferred_foods,
      :days
    ])
    |> Map.put(:user_id, user_id)
  end

  def attrs_for({sex, exercise, age_band}, user_id) do
    attrs_for(get(sex, exercise, age_band), user_id)
  end

  @doc "Instantiates a preset into `user_id`'s account."
  def create_for_user(user_id, sex, exercise, age_band) do
    get(sex, exercise, age_band)
    |> attrs_for(user_id)
    |> MealBlueprints.create_blueprint()
  end

  # ── descriptor construction ──────────────────────────────────────────────

  defp build(sex, exercise, age_band) do
    calories = @calories |> Map.fetch!(sex) |> Map.fetch!({age_band, exercise})

    %{
      key: "#{sex}_#{age_band}s_#{exercise}",
      name: name(sex, exercise, age_band, calories),
      description: description(sex, exercise, age_band, calories),
      sex: sex,
      exercise: exercise,
      age_band: age_band,
      daily_calories: calories,
      # Blueprint-level "general" targets (apply across every day).
      required_nutrients: blueprint_required_nutrients(sex, age_band),
      avoid_nutrients: [],
      required_compounds: [],
      avoid_compounds: [],
      preferred_foods: blueprint_preferred_foods(),
      days: days(exercise, calories)
    }
  end

  defp name(sex, exercise, age_band, calories) do
    "#{sex_label(sex)} · #{age_band}s · #{exercise_label(exercise)} (#{calories} kcal/day)"
  end

  defp description(sex, exercise, age_band, calories) do
    "Starter targets for a #{sex_noun(sex)} in their #{age_band}s with a " <>
      "#{exercise_phrase(exercise)} routine — about #{calories} kcal/day across five " <>
      "meals. Adjust to taste."
  end

  # ── day / meal target construction ───────────────────────────────────────

  # A "basic" blueprint repeats the same daily calorie aim + macros across all 7
  # days; the meal rows carry only macros (the "general" targets live on the
  # blueprint).
  defp days(exercise, calories) do
    meals = Enum.map(MealType.values(), &meal_target(&1, exercise))

    for day_index <- 1..7 do
      %{day_index: day_index, total_calorie_target: calories, meals: meals}
    end
  end

  # The same macro percentage split applies to every slot (a ratio, not an
  # amount); the day carries the absolute calorie aim.
  defp meal_target(meal_type, exercise) do
    Map.put(Map.fetch!(@macro_split, exercise), :meal_type, meal_type)
  end

  # Blueprint-level unions across the five slots.
  defp blueprint_required_nutrients(sex, age_band) do
    MealType.values()
    |> Enum.flat_map(&required_nutrients(&1, sex, age_band))
    |> Enum.uniq()
  end

  defp blueprint_preferred_foods do
    MealType.values()
    |> Enum.flat_map(&preferred_foods/1)
    |> Enum.uniq()
  end

  defp preferred_foods("breakfast"), do: ["eggs", "Greek yogurt", "oats", "berries", "nuts"]
  defp preferred_foods("morning_snack"), do: ["fruit", "nuts", "yogurt"]

  defp preferred_foods("lunch"),
    do: ["lean poultry", "legumes", "leafy greens", "whole grains", "olive oil"]

  defp preferred_foods("afternoon_snack"), do: ["vegetables", "hummus", "cheese", "nuts"]
  defp preferred_foods("dinner"), do: ["fish", "poultry", "vegetables", "legumes", "whole grains"]

  # Base per-slot micronutrient emphasis, plus life-stage additions folded into
  # breakfast (reproductive-age iron/folate for women, bone health from the 50s,
  # B12/D for older adults).
  defp required_nutrients(meal_type, sex, age_band) do
    (base_required(meal_type) ++ life_stage_required(meal_type, sex, age_band))
    |> Enum.uniq()
  end

  defp base_required("breakfast"), do: ["Vitamin C", "Fiber"]
  defp base_required("morning_snack"), do: ["Fiber"]
  defp base_required("lunch"), do: ["Iron", "Fiber"]
  defp base_required("afternoon_snack"), do: []
  defp base_required("dinner"), do: ["Omega-3", "Fiber"]

  # Life-stage additions are cumulative (a 60s woman gets both the
  # post-menopausal bone-health set and the older-adult set), folded into
  # breakfast only.
  defp life_stage_required("breakfast", sex, age) do
    reproductive_age = if sex == :female and age in [20, 30, 40], do: ["Iron", "Folate"], else: []
    bone_health = if sex == :female and age >= 50, do: ["Calcium", "Vitamin D"], else: []
    older_adult = if age >= 60, do: ["Vitamin B12", "Vitamin D"], else: []

    reproductive_age ++ bone_health ++ older_adult
  end

  defp life_stage_required(_meal_type, _sex, _age), do: []

  # ── labels ───────────────────────────────────────────────────────────────

  defp sex_label(:female), do: "Female"
  defp sex_label(:male), do: "Male"

  defp sex_noun(:female), do: "woman"
  defp sex_noun(:male), do: "man"

  defp exercise_label(:none), do: "No exercise"
  defp exercise_label(:some), do: "Some exercise"
  defp exercise_label(:regular), do: "Regular exercise"

  defp exercise_phrase(:none), do: "sedentary (no exercise)"
  defp exercise_phrase(:some), do: "moderately active (some exercise)"
  defp exercise_phrase(:regular), do: "active (regular exercise)"
end
