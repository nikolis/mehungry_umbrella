defmodule Mehungry.MealBlueprints.DietPatterns do
  @moduledoc """
  Ready-made "diet pattern" starter blueprints — named eating patterns (rather
  than the demographic `Presets`) a nutritionist or user can instantiate in one
  click: **Mediterranean** and **Low-FODMAP**.

  Each pattern is a **self-contained meal blueprint** — it carries its own
  required/avoid compound + nutrient tags and preferred/avoid food lists, so it
  needs no backing `Health.Condition`. `attrs_for/2` builds the
  `create_blueprint/1` attrs from a descriptor; `create_for_user/2` and
  `create_missing_for_user/1` instantiate them into a user's account.

  The nutritionist blueprint library (and the admin "Seed diet patterns" button on
  `/professional/health`) call `create_missing_for_user/1`. Everything is driven
  off `all/0`, so adding a new pattern here surfaces it in every button
  automatically.

  The two patterns differ in shape:

    * **Mediterranean** is an *encourage* pattern (like the shipped
      "Anti-Inflammatory" indication): encouraged nutrients/compounds + preferred
      foods, higher-fat macro split for olive oil.
    * **Low-FODMAP** is an *avoidance* pattern: its defining lever is
      `avoid_foods` (onion, garlic, wheat…) plus the FODMAP compound. Those avoid
      lists are enforced during generation by
      `Mehungry.AI.Agents.MealPlanAgent`.

  ## Usage

      Mehungry.MealBlueprints.DietPatterns.all()                  # descriptors (for a picker)
      {:ok, bp} = Mehungry.MealBlueprints.DietPatterns.create_for_user(user_id, :low_fodmap)
  """

  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints

  @keys [:mediterranean, :low_fodmap]

  @doc "All diet-pattern descriptors (for rendering a picker)."
  def all, do: Enum.map(@keys, &build/1)

  @doc "The descriptor for a pattern key (`:mediterranean | :low_fodmap`)."
  def get(key) when key in @keys, do: build(key)

  @doc "The supported pattern keys."
  def keys, do: @keys

  # ── per-user instantiation ─────────────────────────────────────────────────

  @doc """
  Full `MealBlueprints.create_blueprint/1` attrs for `user_id` from a descriptor
  (or a pattern key). The blueprint is self-contained — it carries its own
  compound/nutrient tags and food lists and links to no condition.
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
      :avoid_foods,
      :days
    ])
    |> Map.put(:user_id, user_id)
  end

  def attrs_for(key, user_id) when key in @keys, do: attrs_for(get(key), user_id)

  @doc "Instantiates a diet pattern into `user_id`'s account."
  def create_for_user(user_id, key) when key in @keys do
    key
    |> attrs_for(user_id)
    |> MealBlueprints.create_blueprint()
  end

  @doc """
  Instantiates every diet pattern the user doesn't already own (matched by name),
  so the button is safe to click repeatedly. Returns `{:ok, created_count}`.
  """
  def create_missing_for_user(user_id) do
    existing = user_id |> MealBlueprints.list_blueprints_for_user() |> MapSet.new(& &1.name)

    created =
      for %{key: key, name: name} <- all(), not MapSet.member?(existing, name) do
        create_for_user(user_id, key)
      end

    {:ok, Enum.count(created, &match?({:ok, _}, &1))}
  end

  # ── descriptor construction ──────────────────────────────────────────────

  defp build(:mediterranean) do
    spec = %{
      name: "Mediterranean Diet",
      description:
        "A Mediterranean eating pattern: olive oil as the main fat, plenty of " <>
          "vegetables, legumes, whole grains and fish, moderate dairy, little red meat.",
      compounds: [
        {"Polyphenols", "polyphenol", "encourage", "moderate", harvard_med_ref()},
        {"Flavonoids", "polyphenol", "encourage", "moderate", harvard_med_ref()}
      ],
      nutrients: [
        {"Omega-3", "encourage", "strong", harvard_med_ref()},
        {"Fiber", "encourage", "moderate", harvard_med_ref()},
        {"Monounsaturated Fat", "encourage", "strong", harvard_med_ref()},
        {"Saturated Fat", "limit", "moderate", harvard_med_ref()},
        {"Added Sugar", "limit", "moderate", harvard_med_ref()},
        {"Sodium", "limit", "limited", harvard_med_ref()}
      ]
    }

    descriptor(:mediterranean, spec, %{
      preferred_foods: [
        "olive oil",
        "fish",
        "legumes",
        "whole grains",
        "vegetables",
        "fruit",
        "nuts",
        "Greek yogurt"
      ],
      avoid_foods: [],
      macro_split: %{protein_pct: 20, carbs_pct: 45, fats_pct: 35}
    })
  end

  defp build(:low_fodmap) do
    spec = %{
      name: "Low-FODMAP Diet",
      description:
        "A low-FODMAP eating pattern (commonly used for IBS): avoid high-FODMAP " <>
          "foods such as onion, garlic, wheat and certain fruits and legumes.",
      compounds: [
        {"FODMAP", "fodmap", "limit", "moderate", monash_ref()}
      ],
      nutrients: []
    }

    descriptor(:low_fodmap, spec, %{
      preferred_foods: [
        "rice",
        "oats",
        "firm tofu",
        "eggs",
        "carrots",
        "zucchini",
        "spinach",
        "strawberries",
        "blueberries",
        "lactose-free yogurt",
        "hard cheese"
      ],
      avoid_foods: [
        "onion",
        "garlic",
        "wheat",
        "rye",
        "apple",
        "pear",
        "watermelon",
        "honey",
        "cashews",
        "pistachios",
        "beans",
        "lentils",
        "chickpeas",
        "milk"
      ],
      macro_split: %{protein_pct: 25, carbs_pct: 45, fats_pct: 30}
    })
  end

  # Assembles a descriptor; the blueprint's compound/nutrient tag arrays are
  # *derived* from the pattern spec so direction stays consistent.
  defp descriptor(key, spec, %{
         preferred_foods: preferred_foods,
         avoid_foods: avoid_foods,
         macro_split: macro_split
       }) do
    %{
      key: key,
      name: spec.name,
      description: spec.description,
      required_compounds: compound_names(spec, ["encourage"]),
      avoid_compounds: compound_names(spec, ["avoid", "limit", "caution"]),
      required_nutrients: nutrient_names(spec, ["encourage"]),
      avoid_nutrients: nutrient_names(spec, ["avoid", "limit", "caution"]),
      preferred_foods: preferred_foods,
      avoid_foods: avoid_foods,
      days: days(macro_split)
    }
  end

  defp compound_names(%{compounds: compounds}, directions) do
    for {name, _type, rec, _ev, _ref} <- compounds, rec in directions, do: name
  end

  defp nutrient_names(%{nutrients: nutrients}, directions) do
    for {name, rec, _ev, _ref} <- nutrients, rec in directions, do: name
  end

  # 7 identical days; each carries the 5 meal slots with the same macro split
  # (a ratio, not an amount). Diet patterns set no per-day calorie aim.
  defp days(macro_split) do
    meals = Enum.map(MealType.values(), &Map.put(macro_split, :meal_type, &1))

    for day_index <- 1..7 do
      %{day_index: day_index, meals: meals}
    end
  end

  defp harvard_med_ref do
    %{
      "label" => "Harvard T.H. Chan — The Mediterranean Diet",
      "url" =>
        "https://nutritionsource.hsph.harvard.edu/healthy-weight/diet-reviews/mediterranean-diet/"
    }
  end

  defp monash_ref do
    %{"label" => "Monash University — Low FODMAP diet", "url" => "https://www.monashfodmap.com/"}
  end
end
