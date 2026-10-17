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
    * **avoid / required nutrients** — a nutrient's **caloric share** (grams ×
      kcal-per-gram ÷ total kcal, as a percent) vs the blueprint's per-nutrient
      threshold (`required_nutrient_pcts` / `avoid_nutrient_pcts`, falling back to
      `Blueprint.default_nutrient_pct/1`). Required is a floor → a match when share
      ≥ target; avoid is a ceiling → a violation when share > target. Computed per meal (meal kcal
      denominator), per day (day kcal), and plan-wide (`overall`). Non-energy
      micronutrients have a 0 kcal/g factor, so their share is ~0. Whole-food
      ingredient meals contribute nutrients too: their logged ingredients are run
      through the same recipe nutrition engine (`NutrientCalculation`) into an
      identical tree, so a directly-logged food counts toward goals exactly like
      the same food inside a recipe.
    * **daily energy** — the day's summed meal calories vs the day's
      `total_calorie_target`, bucketed `:under | :ok | :over` on a ±10 % band.

  Compound resolution unions the canonical species layer
  (`FoundementalFood` → `SpeciesCompoundRelationship`) with direct ingredient-level
  facts (`IngredientCompoundRelationship`), in two batched queries regardless of
  meal count.

  ## Shapes

      analyze(blueprint, plan_meals) :: %{
        meals:   %{meal_id => %{violations: [entry], matches: [entry]}},
        days:    %{day_index => day_report},
        overall: %{nutrient_grams: %{blueprint_label => amount}, total_kcal: number,
                   days: [%{nutrient_grams: ..., total_kcal: number}]}
      }

      entry :: %{kind: :compound | :nutrient, name: String.t(),
                 direction: :avoid | :required, via: :direct | :family,
                 # nutrient entries only, by mode:
                 mode: :pct | :amount, target: number,
                 pct: integer,     # pct mode: measured caloric share
                 amount: number}   # amount mode: measured total in the nutrient's unit

      day_report :: %{
        calorie_total: number, calorie_target: integer | nil,
        calorie_status: :no_target | :under | :ok | :over,
        calorie_delta: number | nil,
        violation_count: non_neg_integer, missing_required: [String.t()]
      }

  Requires `plan_meals` preloaded with `recipe: [recipe_ingredients: :ingredient]`
  and `ingredients: :ingredient`, and `blueprint` with `days` (for calorie targets) plus its
  compound/nutrient arrays — see `MealBlueprints.plan_compatibility/2`.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.Compounds
  alias Mehungry.Food.IngredientNutrient
  alias Mehungry.Food.Nutrition.FattyAcidMatcher
  alias Mehungry.Food.NutrientCalculation
  alias Mehungry.Food.NutrientNameNormalizer
  alias Mehungry.Health.NutrientTargets
  alias Mehungry.MealBlueprints.Blueprint

  # Blueprint fatty-acid *family* labels. Recipes store the individual acids by
  # their raw USDA notation (e.g. "PUFA 20:5 n-3 (EPA)"), never an "Omega-3"
  # aggregate, so these are resolved through `FattyAcidMatcher` rather than by
  # name equality.
  @omega_labels ["Omega-3", "Omega-6", "Omega-9"]

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
    labels = target_labels(targets)
    compounds_by_ingredient = resolve_compounds(plan_meals)
    gram_ids = NutrientCalculation.gram_unit_ids()

    # Resolve each meal's `label => grams` once (recipe tree or whole-food
    # ingredient tree — see `meal_nutrient_nodes/2`), keyed by meal id, so the
    # per-meal/day/overall passes are cheap lookups rather than re-derivations.
    amounts_by_meal =
      Map.new(plan_meals, fn meal -> {meal.id, meal_label_amounts(meal, labels, gram_ids)} end)

    # Likewise resolve each meal's calories exactly once here, where `gram_ids`
    # is in scope — the per-meal/day/overall passes all read this map. (Doing it
    # lazily inside the day/overall passes re-derived each ingredient meal's
    # energy several times and, for whole-food ingredient meals, issued a
    # per-ingredient `Repo.preload` each time — an N+1 on the hot calendar path.)
    kcal_by_meal =
      Map.new(plan_meals, fn meal -> {meal.id, meal_calories(meal, gram_ids)} end)

    meal_reports =
      Map.new(plan_meals, fn meal ->
        {meal.id,
         meal_report(meal, targets, amounts_by_meal[meal.id], kcal_by_meal[meal.id],
           compounds_by_ingredient)}
      end)

    %{
      meals: meal_reports,
      days:
        build_day_reports(
          blueprint,
          plan_meals,
          targets,
          amounts_by_meal,
          kcal_by_meal,
          compounds_by_ingredient
        ),
      overall: build_overall(plan_meals, amounts_by_meal, kcal_by_meal)
    }
  end

  # ── entity matching (recipes / ingredients vs a blueprint's targets) ──────────

  @doc """
  Matches a list of **recipes** against `blueprint`'s compound + nutrient targets,
  returning `%{recipe_id => %{matches: [entry], violations: [entry]}}` (see the
  moduledoc `entry` shape). This is the single-entity analogue of `analyze/2`: a
  recipe is treated as a one-serving meal, so it reuses the exact same compound
  resolution and nutrient caloric-share math — no duplicated calculation (the
  REST layer must reuse this, never re-derive it).

  Unlike `analyze/2` the compound side is resolved **by recipe id in two batched
  queries** rather than from preloaded `recipe_ingredients`, so callers can pass
  the lightweight recipe rows a feed/search list already has (only `id`,
  `servings`, and the stored `nutrients` map are read). A recipe with no stored
  `nutrients` simply contributes no nutrient entries.
  """
  def match_recipes(_blueprint, []), do: %{}

  def match_recipes(blueprint, recipes) do
    targets = normalize_targets(blueprint)
    labels = target_labels(targets)
    gram_ids = NutrientCalculation.gram_unit_ids()
    compounds_by_recipe = resolve_recipe_compounds(Enum.map(recipes, & &1.id))

    Map.new(recipes, fn recipe ->
      meal = %{id: recipe.id, recipe_id: recipe.id, recipe: recipe, ingredients: []}
      nutrient_grams = meal_label_amounts(meal, labels, gram_ids)
      meal_kcal = meal_calories(meal, gram_ids)
      comps = Map.get(compounds_by_recipe, recipe.id, [])

      violations =
        compound_entries(comps, targets.avoid_compound, :avoid) ++
          nutrient_entries(nutrient_grams, meal_kcal, targets.avoid_nutrient, :avoid)

      matches =
        compound_entries(comps, targets.required_compound, :required) ++
          nutrient_entries(nutrient_grams, meal_kcal, targets.required_nutrient, :required)

      {recipe.id, %{violations: dedupe_entries(violations), matches: dedupe_entries(matches)}}
    end)
  end

  @doc """
  Matches a list of **ingredients** against `blueprint`'s targets, returning
  `%{ingredient_id => %{matches: [entry], violations: [entry]}}`.

  An ingredient carries no serving/quantity, so its nutrient side cannot use the
  caloric-share math `match_recipes/2` uses. Instead it reuses the `Health`
  per-100g classification (`NutrientTargets` thresholds): an ingredient whose
  per-100g value for a target nutrient crosses the "high in" threshold matches a
  `required` nutrient (good source) or violates an `avoid` one. Compound matching
  is identical to recipes/plans (species-layer ∪ direct ingredient facts). Blueprint
  nutrient names with no known per-100g threshold contribute no ingredient entries.
  """
  def match_ingredients(_blueprint, []), do: %{}

  def match_ingredients(blueprint, ingredients) do
    targets = normalize_targets(blueprint)
    ingredient_ids = Enum.map(ingredients, & &1.id)
    compounds_by_ingredient = resolve_compounds_for_ids(ingredient_ids)
    nutrient_entries_by_ingredient = ingredient_nutrient_entries(ingredient_ids, targets)

    Map.new(ingredients, fn ingredient ->
      comps = Map.get(compounds_by_ingredient, ingredient.id, [])
      {n_matches, n_violations} = Map.get(nutrient_entries_by_ingredient, ingredient.id, {[], []})

      violations = compound_entries(comps, targets.avoid_compound, :avoid) ++ n_violations
      matches = compound_entries(comps, targets.required_compound, :required) ++ n_matches

      {ingredient.id, %{violations: dedupe_entries(violations), matches: dedupe_entries(matches)}}
    end)
  end

  # Ingredient-id-keyed compound resolution (species layer ∪ direct facts), shared
  # with `resolve_compounds/1` via the same batched row queries.
  defp resolve_compounds_for_ids([]), do: %{}

  defp resolve_compounds_for_ids(ingredient_ids) do
    (species_compound_rows(ingredient_ids) ++ ingredient_compound_rows(ingredient_ids))
    |> Enum.group_by(
      fn {ing_id, _name, _type} -> ing_id end,
      fn {_ing_id, name, type} -> %{name: name, type: type} end
    )
    |> Map.new(fn {ing_id, comps} -> {ing_id, Enum.uniq_by(comps, & &1.name)} end)
  end

  # Recipe-id-keyed compound resolution: the same species/ingredient facts as
  # `resolve_compounds/1`, but joined through `recipe_ingredients` so a feed/search
  # recipe row needs no preload. Two batched queries regardless of recipe count.
  defp resolve_recipe_compounds([]), do: %{}

  defp resolve_recipe_compounds(recipe_ids) do
    (recipe_species_compound_rows(recipe_ids) ++ recipe_ingredient_compound_rows(recipe_ids))
    |> Enum.group_by(
      fn {rid, _name, _type} -> rid end,
      fn {_rid, name, type} -> %{name: name, type: type} end
    )
    |> Map.new(fn {rid, comps} -> {rid, Enum.uniq_by(comps, & &1.name)} end)
  end

  defp recipe_species_compound_rows(recipe_ids) do
    Repo.all(
      from(ri in Mehungry.Food.RecipeIngredient,
        join: ff in FoundementalFood,
        on: ff.ingredient_id == ri.ingredient_id,
        join: scr in SpeciesCompoundRelationship,
        on: scr.foundemental_species_id == ff.foundemental_species_id,
        join: c in Compound,
        on: c.id == scr.compound_id,
        where: ri.recipe_id in ^recipe_ids and scr.relationship_type != "absent",
        select: {ri.recipe_id, c.name, c.compound_type}
      )
    )
  end

  defp recipe_ingredient_compound_rows(recipe_ids) do
    Repo.all(
      from(ri in Mehungry.Food.RecipeIngredient,
        join: r in IngredientCompoundRelationship,
        on: r.ingredient_id == ri.ingredient_id,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: ri.recipe_id in ^recipe_ids and r.relationship_type != "absent",
        select: {ri.recipe_id, c.name, c.compound_type}
      )
    )
  end

  # Per-ingredient nutrient match/violation entries from the per-100g USDA values.
  # Reuses the `Health.NutrientTargets` label→nutrient-ids + "high in" threshold
  # map: a required label crossed → a match, an avoid label crossed → a violation.
  # Returns `%{ingredient_id => {matches, violations}}`.
  defp ingredient_nutrient_entries([], _targets), do: %{}

  defp ingredient_nutrient_entries(ingredient_ids, targets) do
    label_dirs = nutrient_label_directions(targets)
    resolved = NutrientTargets.resolve_labels(Map.keys(label_dirs))

    specs =
      Enum.flat_map(resolved, fn {label, {ids, threshold}} ->
        [%{label: label, direction: label_dirs[label], ids: MapSet.new(ids), threshold: threshold}]
      end)

    case specs do
      [] ->
        %{}

      specs ->
        nutrient_ids = specs |> Enum.flat_map(&MapSet.to_list(&1.ids)) |> Enum.uniq()

        Repo.all(
          from(inx in IngredientNutrient,
            where: inx.ingredient_id in ^ingredient_ids and inx.nutrient_id in ^nutrient_ids,
            select: {inx.ingredient_id, inx.nutrient_id, inx.amount}
          )
        )
        |> Enum.group_by(fn {iid, _, _} -> iid end, fn {_, nid, amt} -> {nid, to_number(amt)} end)
        |> Map.new(fn {iid, amounts} -> {iid, ingredient_nutrient_split(amounts, specs)} end)
    end
  end

  # required/avoid blueprint nutrient labels → their direction (required wins a tie).
  defp nutrient_label_directions(targets) do
    avoid = Map.new(targets.avoid_nutrient, &{&1.name, :avoid})
    required = Map.new(targets.required_nutrient, &{&1.name, :required})
    Map.merge(avoid, required)
  end

  # Split one ingredient's `{nutrient_id, per_100g}` pairs into {matches, violations}
  # entries over the resolved specs it crosses (highest crossing amount per spec).
  defp ingredient_nutrient_split(amounts, specs) do
    specs
    |> Enum.flat_map(fn spec ->
      crossed =
        amounts
        |> Enum.filter(fn {nid, amt} -> MapSet.member?(spec.ids, nid) and amt >= spec.threshold end)
        |> Enum.map(&elem(&1, 1))

      case crossed do
        [] ->
          []

        amts ->
          [
            %{
              kind: :nutrient,
              name: spec.label,
              direction: spec.direction,
              via: :direct,
              mode: :per_100g,
              per_100g: Enum.max(amts),
              threshold: spec.threshold
            }
          ]
      end
    end)
    |> Enum.split_with(&(&1.direction == :required))
  end

  # Every nutrient label the blueprint references (required ∪ avoid). The recipe
  # nutrient tree is resolved into a `label => grams` map over exactly these.
  defp target_labels(targets) do
    (targets.avoid_nutrient ++ targets.required_nutrient)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  # ── target normalization ────────────────────────────────────────────────────

  defp normalize_targets(blueprint) do
    %{
      avoid_compound: split_compounds(blueprint.avoid_compounds),
      required_compound: split_compounds(blueprint.required_compounds),
      required_compound_tokens: blueprint.required_compounds || [],
      avoid_nutrient:
        nutrient_targets(
          blueprint.avoid_nutrients,
          blueprint.avoid_nutrient_pcts,
          blueprint.avoid_nutrient_modes
        ),
      required_nutrient:
        nutrient_targets(
          blueprint.required_nutrients,
          blueprint.required_nutrient_pcts,
          blueprint.required_nutrient_modes
        )
    }
  end

  # A blueprint nutrient target = its name + resolved `%{mode, value}` (pct caloric
  # share or an absolute per-day amount in the nutrient's unit).
  defp nutrient_targets(names, values, modes) do
    (names || [])
    |> Enum.map(fn name -> Map.put(nutrient_target(values, modes, name), :name, name) end)
  end

  @doc """
  Resolves a nutrient's threshold as `%{mode: :pct | :amount, value: number}`.
  With no stored mode it falls back to the name-aware `Blueprint`
  `default_nutrient_mode/1` (fiber → amount, everything else → pct), and with no
  stored value to the matching name-aware default
  (`default_nutrient_amount/1` / `default_nutrient_pct/1`). Shared with the
  context's week panel.
  """
  def nutrient_target(values, modes, name) do
    values = values || %{}
    modes = modes || %{}

    case Map.get(modes, name) || Blueprint.default_nutrient_mode(name) do
      "amount" ->
        %{mode: :amount, value: to_number(Map.get(values, name, Blueprint.default_nutrient_amount(name)))}

      _ ->
        %{
          mode: :pct,
          value: to_number(Map.get(values, name, Blueprint.default_nutrient_pct(name)))
        }
    end
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
      from(ff in FoundementalFood,
        join: scr in SpeciesCompoundRelationship,
        on: scr.foundemental_species_id == ff.foundemental_species_id,
        join: c in Compound,
        on: c.id == scr.compound_id,
        where: ff.ingredient_id in ^ingredient_ids and scr.relationship_type != "absent",
        select: {ff.ingredient_id, c.name, c.compound_type}
      )
    )
  end

  # Direct ingredient-level facts (union with the species layer for coverage).
  defp ingredient_compound_rows(ingredient_ids) do
    Repo.all(
      from(r in IngredientCompoundRelationship,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.ingredient_id in ^ingredient_ids and r.relationship_type != "absent",
        select: {r.ingredient_id, c.name, c.compound_type}
      )
    )
  end

  # A meal's ingredient ids = its recipe's ingredients ∪ its direct ingredient
  # children (a meal may have both).
  defp meal_ingredient_ids(meal) do
    Enum.uniq(recipe_ingredient_ids(meal) ++ child_ingredient_ids(meal))
  end

  defp recipe_ingredient_ids(%{recipe_id: rid, recipe: %{recipe_ingredients: ris}})
       when not is_nil(rid) and is_list(ris),
       do: Enum.map(ris, & &1.ingredient_id)

  defp recipe_ingredient_ids(_), do: []

  defp child_ingredient_ids(%{ingredients: ingredients}) when is_list(ingredients),
    do: Enum.map(ingredients, & &1.ingredient_id)

  defp child_ingredient_ids(_), do: []

  # ── per-meal report ───────────────────────────────────────────────────────────

  defp meal_report(meal, targets, nutrient_grams, meal_kcal, compounds_by_ingredient) do
    comps = meal_compounds(meal, compounds_by_ingredient)

    violations =
      compound_entries(comps, targets.avoid_compound, :avoid) ++
        nutrient_entries(nutrient_grams, meal_kcal, targets.avoid_nutrient, :avoid)

    matches =
      compound_entries(comps, targets.required_compound, :required) ++
        nutrient_entries(nutrient_grams, meal_kcal, targets.required_nutrient, :required)

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

  # A nutrient target contributes an entry when its measured value crosses its
  # threshold for the direction: required is a floor (≥), avoid is a ceiling (>,
  # at/below the limit is fine). In pct mode the measured value is the caloric
  # share; in amount mode it is the scope's total in the nutrient's own unit.
  # `amounts_map` is keyed by blueprint nutrient label (see `meal_label_amounts/2`).
  defp nutrient_entries(amounts_map, total_kcal, targets, direction) do
    Enum.flat_map(targets, fn %{name: name, mode: mode, value: value} ->
      amount = Map.get(amounts_map, name, 0)

      {measured, extra} =
        case mode do
          :pct ->
            pct = nutrient_pct(name, amount, total_kcal)
            {pct, %{mode: :pct, pct: round(pct)}}

          :amount ->
            {to_number(amount), %{mode: :amount, amount: round(to_number(amount))}}
        end

      if nutrient_threshold_crossed?(direction, measured, value) do
        [
          Map.merge(
            %{kind: :nutrient, name: name, direction: direction, via: :direct, target: value},
            extra
          )
        ]
      else
        []
      end
    end)
  end

  @doc """
  Whether a nutrient's caloric `pct` crosses its `target` for the given direction:
  required is a floor (`pct >= target`), avoid is a ceiling (`pct > target`).
  """
  def nutrient_threshold_crossed?(:required, pct, target), do: pct >= target
  def nutrient_threshold_crossed?(:avoid, pct, target), do: pct > target

  # Caloric share of a nutrient: grams × kcal-per-gram / total kcal, as a percent.
  defp nutrient_pct(_name, _grams, total_kcal) when total_kcal <= 0, do: 0.0

  defp nutrient_pct(name, grams, total_kcal),
    do: to_number(grams) * nutrient_kcal_factor(name) / total_kcal * 100

  # kcal per gram for the energy-bearing nutrients; everything else (micros) is 0,
  # so its caloric share is 0.
  def nutrient_kcal_factor(name) do
    n = String.downcase(to_string(name))

    cond do
      String.contains?(n, "protein") ->
        4

      String.contains?(n, "alcohol") ->
        7

      String.contains?(n, "fiber") or String.contains?(n, "fibre") ->
        2

      String.contains?(n, "sugar") ->
        4

      String.contains?(n, "starch") ->
        4

      String.contains?(n, "carbohydrate") or String.contains?(n, "carbs") ->
        4

      # Fats incl. fatty-acid classes the "fat"/"lipid" check misses (Omega-3/6,
      # PUFA/MUFA) — all ~9 kcal/g.
      String.contains?(n, "lipid") or String.contains?(n, "fat") or
        String.contains?(n, "omega") or String.contains?(n, "pufa") or
          String.contains?(n, "mufa") ->
        9

      true ->
        0
    end
  end

  @doc """
  A nutrient's caloric share (percent) over the `overall` summary returned by
  `analyze/2` (`%{nutrient_grams: ..., total_kcal: ...}`) — used for pct-mode
  week checks (scale-invariant, so week ratio ≈ daily ratio).
  """
  def overall_nutrient_pct(name, %{nutrient_grams: grams, total_kcal: total_kcal}) do
    nutrient_pct(name, Map.get(grams, name, 0), total_kcal)
  end

  @doc """
  A nutrient's per-day totals (native unit) across the days that have meals, from
  the `overall` summary — used for amount-mode week checks (a per-day cap/floor
  must be evaluated day-by-day, not on the week total).
  """
  def overall_nutrient_day_amounts(name, %{days: days}) do
    Enum.map(days, fn day -> to_number(Map.get(day.nutrient_grams, name, 0)) end)
  end

  def overall_nutrient_day_amounts(_name, _overall), do: []

  @doc """
  A nutrient's total measured amount (native unit) across the whole week, from the
  `overall` summary — the current quantity shown alongside a pct target.
  """
  def overall_nutrient_amount(name, %{nutrient_grams: grams}) do
    to_number(Map.get(grams, name, 0))
  end

  def overall_nutrient_amount(_name, _overall), do: 0

  defp dedupe_entries(entries), do: Enum.uniq_by(entries, &{&1.kind, &1.name})

  # ── nutrient amounts (recipe nutrient tree) ───────────────────────────────────

  # Resolves a meal's nutrient tree into a `label => grams` map over the
  # blueprint's target `labels`. A recipe meal uses its stored tree scaled by the
  # servings consumed (`recipe_portions/1 / servings`, the same factor
  # `recipe_calories/1` applies to energy); a whole-food ingredient meal builds
  # the *same* tree shape from its logged ingredients via the recipe engine,
  # already scaled to the logged quantity — so a directly-logged food counts
  # toward goals exactly like the same food inside a recipe.
  defp meal_label_amounts(meal, labels, gram_ids) do
    {nodes, scale} = meal_nutrient_nodes(meal, gram_ids)
    Map.new(labels, fn label -> {label, sum_label_in_tree(nodes, label) * scale} end)
  end

  defp meal_nutrient_nodes(
         %{recipe_id: rid, recipe: %{nutrients: nutrients} = recipe} = meal,
         _gram_ids
       )
       when not is_nil(rid) and is_map(nutrients),
       do: {Map.values(nutrients), recipe_portions(meal) / recipe_servings(recipe)}

  defp meal_nutrient_nodes(%{ingredients: [_ | _] = ingredients}, gram_ids) do
    nutrient_lists =
      ingredients
      |> Enum.map(&ingredient_scaled_nutrients(&1, gram_ids))
      |> Enum.reject(&(&1 == []))

    case nutrient_lists do
      [] -> {[], 1.0}
      lists -> {Map.values(NutrientCalculation.nutrient_tree(lists)), 1.0}
    end
  end

  defp meal_nutrient_nodes(_meal, _gram_ids), do: {[], 1.0}

  # One logged ingredient → its gram-scaled nutrient list (the recipe engine's
  # per-ingredient input). Returns [] when the nutrient/portion data needed to
  # scale it isn't loaded, so the meal degrades to "no contribution" rather than
  # triggering lazy N+1 loads.
  defp ingredient_scaled_nutrients(%{ingredient: %{} = ingredient} = ing, gram_ids) do
    if ingredient_nutrients_loaded?(ingredient) do
      gram_weight =
        NutrientCalculation.calculate_gram_weight(
          ingredient,
          Map.get(ing, :measurement_unit_id),
          Map.get(ing, :ingredient_portion_id),
          Map.get(ing, :quantity),
          gram_ids
        )

      NutrientCalculation.build_nutrient_list(ingredient, gram_weight)
    else
      []
    end
  end

  defp ingredient_scaled_nutrients(_ing, _gram_ids), do: []

  defp ingredient_nutrients_loaded?(ingredient) do
    Ecto.assoc_loaded?(ingredient.ingredient_nutrients) and
      Ecto.assoc_loaded?(ingredient.ingredient_portions)
  end

  # Sums the grams a blueprint label accounts for across the nutrient tree. A node
  # that matches the label is counted and its subtree is *not* descended (so a
  # "Dietary Fiber" aggregate isn't double-counted with its soluble/insoluble
  # children); otherwise we recurse so leaf fatty acids under "Polyunsaturated Fat"
  # (whose parent never matches "Omega-3") are reached and summed.
  defp sum_label_in_tree(nodes, label) when is_list(nodes) do
    Enum.reduce(nodes, 0.0, fn node, acc -> acc + sum_label_node(node, label) end)
  end

  defp sum_label_in_tree(_nodes, _label), do: 0.0

  defp sum_label_node(node, label) when is_map(node) do
    name = node_field(node, "name", :name)
    amount = to_number(node_field(node, "amount", :amount))
    children = node_field(node, "children", :children) || []

    if is_binary(name) and amount > 0 and label_matches?(label, name) do
      amount
    else
      sum_label_in_tree(List.wrap(children), label)
    end
  end

  defp sum_label_node(_node, _label), do: 0.0

  # Whether a recipe nutrient-tree node `name` contributes to a blueprint `label`.
  # Fatty-acid families (Omega-3/6/9) resolve through `FattyAcidMatcher` since the
  # tree stores individual acids by raw USDA notation; the literal-name fallback
  # keeps an explicit "Omega-3" node (used in tests / hand-authored data) matching.
  # Everything else collapses both sides through `NutrientNameNormalizer` so the
  # canonical label ("Iron", "Fiber", "Vitamin C") matches the stored USDA name
  # ("Iron, Fe", "Dietary Fiber", "Vitamin C, total ascorbic acid").
  defp label_matches?(label, name) when is_binary(name) do
    if label in @omega_labels do
      (FattyAcidMatcher.match(name) || %{})[:omega_family] == label or
        NutrientNameNormalizer.normalize(name) == label
    else
      NutrientNameNormalizer.normalize(name) == NutrientNameNormalizer.normalize(label)
    end
  end

  defp label_matches?(_label, _name), do: false

  # Sum a list of `label => grams` maps into one.
  defp merge_grams(maps) do
    Enum.reduce(maps, %{}, fn m, acc -> Map.merge(acc, m, fn _k, a, b -> a + b end) end)
  end

  # Week/plan-wide nutrient amounts (label keys) + total kcal for pct-mode checks,
  # plus a per-day breakdown (days with meals only) for amount-mode checks.
  defp build_overall(plan_meals, amounts_by_meal, kcal_by_meal) do
    grams =
      plan_meals
      |> Enum.map(&amounts_by_meal[&1.id])
      |> merge_grams()

    days =
      plan_meals
      |> Enum.group_by(& &1.day_index)
      |> Enum.map(fn {day_index, meals} ->
        %{
          day_index: day_index,
          nutrient_grams: meals |> Enum.map(&amounts_by_meal[&1.id]) |> merge_grams(),
          total_kcal: day_calories(meals, kcal_by_meal)
        }
      end)

    %{nutrient_grams: grams, total_kcal: day_calories(plan_meals, kcal_by_meal), days: days}
  end

  # ── per-day report ────────────────────────────────────────────────────────────

  defp build_day_reports(
         blueprint,
         plan_meals,
         targets,
         amounts_by_meal,
         kcal_by_meal,
         compounds_by_ingredient
       ) do
    meals_by_day = Enum.group_by(plan_meals, & &1.day_index)

    Map.new(blueprint.days, fn day ->
      meals = Map.get(meals_by_day, day.day_index, [])

      {day.day_index,
       report_for_day(day, meals, targets, amounts_by_meal, kcal_by_meal, compounds_by_ingredient)}
    end)
  end

  defp report_for_day(day, meals, targets, amounts_by_meal, kcal_by_meal, compounds_by_ingredient) do
    day_comps =
      meals
      |> Enum.flat_map(&meal_compounds(&1, compounds_by_ingredient))
      |> Enum.uniq_by(& &1.name)

    day_nutrient_grams = meals |> Enum.map(&amounts_by_meal[&1.id]) |> merge_grams()
    day_kcal = day_calories(meals, kcal_by_meal)

    violations =
      compound_entries(day_comps, targets.avoid_compound, :avoid) ++
        nutrient_entries(day_nutrient_grams, day_kcal, targets.avoid_nutrient, :avoid)

    {status, delta} = calorie_status(day_kcal, day.total_calorie_target)

    %{
      calorie_total: round(day_kcal),
      calorie_target: day.total_calorie_target,
      calorie_status: status,
      calorie_delta: delta && round(delta),
      violation_count: length(dedupe_entries(violations)),
      missing_required: missing_required(targets, day_comps, day_nutrient_grams, day_kcal)
    }
  end

  # Required blueprint targets that this day fails to satisfy: compounds that are
  # absent, and nutrients that fall short of their threshold (caloric share in pct
  # mode, or the day's total in amount mode).
  defp missing_required(targets, day_comps, day_nutrient_grams, day_kcal) do
    missing_compounds =
      Enum.reject(targets.required_compound_tokens, &compound_token_present?(&1, day_comps))

    missing_nutrients =
      targets.required_nutrient
      |> Enum.reject(fn %{name: name, mode: mode, value: value} ->
        amount = Map.get(day_nutrient_grams, name, 0)

        measured =
          case mode do
            :pct -> nutrient_pct(name, amount, day_kcal)
            :amount -> to_number(amount)
          end

        nutrient_threshold_crossed?(:required, measured, value)
      end)
      |> Enum.map(& &1.name)

    missing_compounds ++ missing_nutrients
  end

  defp compound_token_present?(token, comps) do
    case Compounds.type_for_family_label(token) do
      nil -> Enum.any?(comps, &(String.downcase(&1.name) == String.downcase(token)))
      type -> Enum.any?(comps, &(&1.type == type))
    end
  end

  # ── calories ──────────────────────────────────────────────────────────────────

  defp day_calories(meals, kcal_by_meal) do
    Enum.reduce(meals, 0.0, fn meal, acc -> Map.get(kcal_by_meal, meal.id, 0.0) + acc end)
  end

  # A meal's energy = its recipe (scaled to the servings actually consumed — see
  # `recipe_portions/1`) plus each of its ingredient children.
  defp meal_calories(meal, gram_ids),
    do: recipe_calories(meal) + ingredients_calories(meal, gram_ids)

  defp recipe_calories(%{recipe_id: rid, recipe: %{} = recipe} = meal) when not is_nil(rid),
    do: recipe_energy(recipe) * recipe_portions(meal) / recipe_servings(recipe)

  defp recipe_calories(_), do: 0.0

  # How many of a recipe's servings this meal consumes, the scale both its energy
  # and its nutrient tree are multiplied by. A plan (`BlueprintPlanMeal`) meal
  # carries no `consume_portions` → one serving (matching the plan→calendar
  # import's `consume_portions: 1`); a real calendar meal threads its logged
  # `consume_portions` so the week panel scales exactly like the calendar's own
  # daily total (`NutrientUtils.consumed_fraction/1`).
  defp recipe_portions(%{consume_portions: c}) when is_number(c) and c >= 0, do: c
  defp recipe_portions(_), do: 1

  defp ingredients_calories(%{ingredients: ingredients}, gram_ids) when is_list(ingredients),
    do: Enum.reduce(ingredients, 0.0, fn ing, acc -> acc + ingredient_calories(ing, gram_ids) end)

  defp ingredients_calories(_, _gram_ids), do: 0.0

  # One logged ingredient's calories, resolved through the **same** recipe nutrition
  # engine the nutrient-grams pass uses (`ingredient_scaled_nutrients/2`): weigh it
  # by its chosen portion/unit × quantity, scale its per-100g nutrients, and read
  # the deduped Energy entry. This keeps energy and nutrient scaling consistent for
  # non-gram units (a "2 medium banana" weighs its two bananas, not "2 g"), and
  # reads only the preloaded assocs — no per-ingredient `Repo.preload`. Degrades to
  # 0 when the nutrient/portion data isn't loaded, matching the grams pass.
  defp ingredient_calories(%{ingredient: %{} = ingredient} = ing, gram_ids) do
    if ingredient_nutrients_loaded?(ingredient) do
      gram_weight =
        NutrientCalculation.calculate_gram_weight(
          ingredient,
          Map.get(ing, :measurement_unit_id),
          Map.get(ing, :ingredient_portion_id),
          Map.get(ing, :quantity),
          gram_ids
        )

      ingredient
      |> NutrientCalculation.build_nutrient_list(gram_weight)
      |> energy_kcal_from_list()
    else
      0.0
    end
  end

  defp ingredient_calories(_ing, _gram_ids), do: 0.0

  # The scaled Energy kcal from a `build_nutrient_list/2` output: pick the single
  # (already deduped) Energy node and convert kJ → kcal when its unit is not kcal.
  defp energy_kcal_from_list(nutrient_list) do
    case Enum.find(nutrient_list, &String.contains?(&1.name, "Energy")) do
      nil ->
        0.0

      %{amount: amount, measurement_unit: unit} ->
        if unit in ["kilocalorie", "kcal"],
          do: to_number(amount),
          else: to_number(amount) / 4.184
    end
  end

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
