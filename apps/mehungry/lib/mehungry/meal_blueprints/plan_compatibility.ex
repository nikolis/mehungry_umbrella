defmodule Mehungry.MealBlueprints.PlanCompatibility do
  @moduledoc """
  Reads a generated `BlueprintPlan`'s meals against the `Blueprint`'s targets and
  reports, per meal and per day, how well the (nutritionist-edited) plan still
  honours the blueprint. This powers the live compatibility badges in the plan
  editor (`MehungryWeb.MealBlueprintLive.Index`).

  Facts checked (all four confirmed in scope):

    * **avoid compounds** — a meal carries an ingredient with a bioactive compound
      the blueprint lists under `avoid_compounds` → a per-meal *violation*.
    * **required compounds** — a meal includes a compound under `required_compounds`
      → a per-meal *match* (positive). Compound tags match either a specific
      compound name **or** a family (`compound_type`) label like "Polyphenols",
      via `Mehungry.Food.Compounds.family_labels/0`.
    * **avoid / required nutrients** — presence of a blueprint nutrient name in the
      recipe's stored nutrient tree. (Recipe meals only; whole-food ingredient
      meals contribute compounds but not nutrients here — a best-effort v1 gap.)
    * **daily energy** — the day's summed meal calories vs the day's
      `total_calorie_target`, bucketed `:under | :ok | :over` on a ±10 % band.

  Compound resolution unions the canonical species layer
  (`FoundementalFood` → `SpeciesCompoundRelationship`) with direct ingredient-level
  facts (`IngredientCompoundRelationship`), in two batched queries regardless of
  meal count.

  ## Shapes

      analyze(blueprint, plan_meals) :: %{
        meals: %{meal_id => %{violations: [entry], matches: [entry]}},
        days:  %{day_index => day_report}
      }

      entry :: %{kind: :compound | :nutrient, name: String.t(),
                 direction: :avoid | :required, via: :direct | :family}

      day_report :: %{
        calorie_total: number, calorie_target: integer | nil,
        calorie_status: :no_target | :under | :ok | :over,
        calorie_delta: number | nil,
        violation_count: non_neg_integer, missing_required: [String.t()]
      }

  Requires `plan_meals` preloaded with `recipe: [recipe_ingredients: :ingredient]`
  and `:ingredient`, and `blueprint` with `days` (for calorie targets) plus its
  compound/nutrient arrays — see `MealBlueprints.plan_compatibility/2`.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.Compounds

  alias Mehungry.Food.{
    Compound,
    FoundementalFood,
    IngredientCompoundRelationship,
    SpeciesCompoundRelationship
  }

  # Fraction of the day's calorie target that counts as "on target".
  @calorie_tolerance 0.10

  @doc "Analyzes `plan_meals` against `blueprint`'s targets. See moduledoc for shapes."
  def analyze(blueprint, plan_meals) do
    targets = normalize_targets(blueprint)
    compounds_by_ingredient = resolve_compounds(plan_meals)

    meal_reports =
      Map.new(plan_meals, fn meal ->
        {meal.id, meal_report(meal, targets, compounds_by_ingredient)}
      end)

    %{
      meals: meal_reports,
      days: build_day_reports(blueprint, plan_meals, targets, compounds_by_ingredient)
    }
  end

  # ── target normalization ────────────────────────────────────────────────────

  defp normalize_targets(blueprint) do
    %{
      avoid_compound: split_compounds(blueprint.avoid_compounds),
      required_compound: split_compounds(blueprint.required_compounds),
      required_compound_tokens: blueprint.required_compounds || [],
      avoid_nutrient: downcased_set(blueprint.avoid_nutrients),
      required_nutrient: downcased_set(blueprint.required_nutrients),
      required_nutrient_tokens: blueprint.required_nutrients || []
    }
  end

  # A blueprint compound tag is either a family display label ("Polyphenols") or a
  # specific compound name; split them so each is matched the right way.
  defp split_compounds(tags) do
    {families, names} =
      (tags || [])
      |> Enum.split_with(&(Compounds.type_for_family_label(&1) != nil))

    %{
      names: MapSet.new(names, &String.downcase/1),
      families: MapSet.new(families, &Compounds.type_for_family_label/1)
    }
  end

  defp downcased_set(list), do: MapSet.new(list || [], &String.downcase/1)

  # ── compound resolution (batched) ─────────────────────────────────────────────

  defp resolve_compounds(plan_meals) do
    ingredient_ids = plan_meals |> Enum.flat_map(&meal_ingredient_ids/1) |> Enum.uniq()

    if ingredient_ids == [] do
      %{}
    else
      (species_compound_rows(ingredient_ids) ++ ingredient_compound_rows(ingredient_ids))
      |> Enum.group_by(
        fn {ing_id, _name, _type} -> ing_id end,
        fn {_ing_id, name, type} -> %{name: name, type: type} end
      )
      |> Map.new(fn {ing_id, comps} -> {ing_id, Enum.uniq_by(comps, & &1.name)} end)
    end
  end

  # Canonical species-layer facts: ingredient → species → (non-absent) compound.
  defp species_compound_rows(ingredient_ids) do
    Repo.all(
      from ff in FoundementalFood,
        join: scr in SpeciesCompoundRelationship,
        on: scr.foundemental_species_id == ff.foundemental_species_id,
        join: c in Compound,
        on: c.id == scr.compound_id,
        where: ff.ingredient_id in ^ingredient_ids and scr.relationship_type != "absent",
        select: {ff.ingredient_id, c.name, c.compound_type}
    )
  end

  # Direct ingredient-level facts (union with the species layer for coverage).
  defp ingredient_compound_rows(ingredient_ids) do
    Repo.all(
      from r in IngredientCompoundRelationship,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.ingredient_id in ^ingredient_ids and r.relationship_type != "absent",
        select: {r.ingredient_id, c.name, c.compound_type}
    )
  end

  defp meal_ingredient_ids(%{recipe_id: rid, recipe: %{recipe_ingredients: ris}})
       when not is_nil(rid) and is_list(ris) do
    Enum.map(ris, & &1.ingredient_id)
  end

  defp meal_ingredient_ids(%{ingredient_id: iid}) when not is_nil(iid), do: [iid]
  defp meal_ingredient_ids(_), do: []

  # ── per-meal report ───────────────────────────────────────────────────────────

  defp meal_report(meal, targets, compounds_by_ingredient) do
    comps = meal_compounds(meal, compounds_by_ingredient)
    nutrients = meal_nutrient_names(meal)

    violations =
      compound_entries(comps, targets.avoid_compound, :avoid) ++
        nutrient_entries(nutrients, targets.avoid_nutrient, :avoid)

    matches =
      compound_entries(comps, targets.required_compound, :required) ++
        nutrient_entries(nutrients, targets.required_nutrient, :required)

    %{violations: dedupe_entries(violations), matches: dedupe_entries(matches)}
  end

  defp meal_compounds(meal, compounds_by_ingredient) do
    meal
    |> meal_ingredient_ids()
    |> Enum.flat_map(&Map.get(compounds_by_ingredient, &1, []))
    |> Enum.uniq_by(& &1.name)
  end

  # Direct matches surface the specific compound; family matches collapse to one
  # badge per family (a recipe with five polyphenols shouldn't render five pills).
  defp compound_entries(comps, %{names: names, families: families}, direction) do
    direct =
      comps
      |> Enum.filter(&MapSet.member?(names, String.downcase(&1.name)))
      |> Enum.map(&%{kind: :compound, name: &1.name, direction: direction, via: :direct})

    family =
      comps
      |> Enum.map(& &1.type)
      |> Enum.filter(&(not is_nil(&1) and MapSet.member?(families, &1)))
      |> Enum.uniq()
      |> Enum.map(fn type ->
        %{
          kind: :compound,
          name: Map.get(Compounds.family_labels(), type, type),
          direction: direction,
          via: :family
        }
      end)

    direct ++ family
  end

  defp nutrient_entries(nutrient_names, target_set, direction) do
    nutrient_names
    |> Enum.filter(&MapSet.member?(target_set, String.downcase(&1)))
    |> Enum.map(&%{kind: :nutrient, name: &1, direction: direction, via: :direct})
  end

  defp dedupe_entries(entries), do: Enum.uniq_by(entries, &{&1.kind, &1.name})

  # ── nutrient presence (recipe nutrient tree) ──────────────────────────────────

  # Recipe meals carry a stored, hierarchical nutrient map (jsonb → string keys on
  # read). Flatten every node (incl. nested vitamins/minerals children) whose
  # amount is > 0 into a name set. Ingredient meals contribute no nutrient names.
  defp meal_nutrient_names(%{recipe_id: rid, recipe: %{nutrients: nutrients}})
       when not is_nil(rid) and is_map(nutrients) do
    nutrients |> Map.values() |> collect_nutrient_names(MapSet.new()) |> MapSet.to_list()
  end

  defp meal_nutrient_names(_), do: []

  defp collect_nutrient_names(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &collect_nutrient_node/2)
  end

  defp collect_nutrient_names(_node, acc), do: acc

  defp collect_nutrient_node(node, acc) do
    name = node_field(node, "name", :name)
    amount = node_field(node, "amount", :amount)
    children = node_field(node, "children", :children) || []

    acc = if is_binary(name) and to_number(amount) > 0, do: MapSet.put(acc, name), else: acc
    collect_nutrient_names(List.wrap(children), acc)
  end

  # ── per-day report ────────────────────────────────────────────────────────────

  defp build_day_reports(blueprint, plan_meals, targets, compounds_by_ingredient) do
    meals_by_day = Enum.group_by(plan_meals, & &1.day_index)

    Map.new(blueprint.days, fn day ->
      meals = Map.get(meals_by_day, day.day_index, [])
      {day.day_index, report_for_day(day, meals, targets, compounds_by_ingredient)}
    end)
  end

  defp report_for_day(day, meals, targets, compounds_by_ingredient) do
    day_comps =
      meals
      |> Enum.flat_map(&meal_compounds(&1, compounds_by_ingredient))
      |> Enum.uniq_by(& &1.name)

    day_nutrients = meals |> Enum.flat_map(&meal_nutrient_names/1) |> Enum.uniq()

    violations =
      compound_entries(day_comps, targets.avoid_compound, :avoid) ++
        nutrient_entries(day_nutrients, targets.avoid_nutrient, :avoid)

    {status, delta} = calorie_status(day_calories(meals), day.total_calorie_target)

    %{
      calorie_total: round(day_calories(meals)),
      calorie_target: day.total_calorie_target,
      calorie_status: status,
      calorie_delta: delta && round(delta),
      violation_count: length(dedupe_entries(violations)),
      missing_required: missing_required(targets, day_comps, day_nutrients)
    }
  end

  # Required tokens (raw blueprint labels) that no meal that day satisfies.
  defp missing_required(targets, day_comps, day_nutrients) do
    nutrient_set = MapSet.new(day_nutrients, &String.downcase/1)

    missing_compounds =
      Enum.reject(targets.required_compound_tokens, &compound_token_present?(&1, day_comps))

    missing_nutrients =
      Enum.reject(targets.required_nutrient_tokens, fn token ->
        MapSet.member?(nutrient_set, String.downcase(token))
      end)

    missing_compounds ++ missing_nutrients
  end

  defp compound_token_present?(token, comps) do
    case Compounds.type_for_family_label(token) do
      nil -> Enum.any?(comps, &(String.downcase(&1.name) == String.downcase(token)))
      type -> Enum.any?(comps, &(&1.type == type))
    end
  end

  # ── calories ──────────────────────────────────────────────────────────────────

  defp day_calories(meals), do: Enum.reduce(meals, 0.0, &(meal_calories(&1) + &2))

  # One consumed portion ≈ one recipe serving — matches the plan→calendar import,
  # which sets consume_portions: 1. Ingredient meals are omitted (no stored energy).
  defp meal_calories(%{recipe_id: rid, recipe: %{} = recipe}) when not is_nil(rid) do
    recipe_energy(recipe) / recipe_servings(recipe)
  end

  defp meal_calories(_), do: 0.0

  defp recipe_energy(%{nutrients: nutrients}) when is_map(nutrients) do
    energy = Map.get(nutrients, "Energy") || Map.get(nutrients, :Energy)
    to_number(node_field(energy, "amount", :amount))
  end

  defp recipe_energy(_), do: 0.0

  defp recipe_servings(%{servings: s}) when is_integer(s) and s > 0, do: s
  defp recipe_servings(_), do: 1

  defp calorie_status(_total, target) when is_nil(target) or target <= 0, do: {:no_target, nil}

  defp calorie_status(total, target) do
    delta = total - target

    status =
      cond do
        total > target * (1 + @calorie_tolerance) -> :over
        total < target * (1 - @calorie_tolerance) -> :under
        true -> :ok
      end

    {status, delta}
  end

  # ── small helpers ─────────────────────────────────────────────────────────────

  defp node_field(node, skey, akey) when is_map(node) do
    cond do
      Map.has_key?(node, skey) -> Map.get(node, skey)
      Map.has_key?(node, akey) -> Map.get(node, akey)
      true -> nil
    end
  end

  defp node_field(_node, _skey, _akey), do: nil

  defp to_number(n) when is_number(n), do: n

  defp to_number(n) when is_binary(n) do
    case Float.parse(n) do
      {f, _} -> f
      :error -> 0
    end
  end

  defp to_number(_), do: 0
end
