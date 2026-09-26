defmodule Mehungry.MealBlueprints do
  @moduledoc """
  The MealBlueprints context — user-owned "7-day meal-plan blueprints".

  A blueprint is a reusable targets document: 7 days, each with an optional
  calorie aim and one target row per calendar meal slot
  (`Mehungry.History.MealType.values/0`). It holds no recipes; a later phase
  feeds its targets to the AI meal planner. See `Mehungry.MealBlueprints.Blueprint`.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints.Blueprint
  alias Mehungry.MealBlueprints.BlueprintPlan
  alias Mehungry.MealBlueprints.BlueprintPlanMeal
  alias Mehungry.MealBlueprints.PlanCompatibility
  alias Mehungry.MealBlueprints.UserBlueprint

  @doc "Lists a user's blueprints, most recent first (lightweight — no deep preload)."
  def list_blueprints_for_user(user_id) do
    Repo.all(from(b in Blueprint, where: b.user_id == ^user_id, order_by: [desc: b.inserted_at]))
  end

  @doc """
  Fetches one blueprint owned by `user_id`, with its full day/meal tree loaded
  and meals ordered by the canonical slot order (string sort ≠ display order).

  Raises `Ecto.NoResultsError` if it does not exist or belongs to another user.
  """
  def get_blueprint!(user_id, id) do
    Blueprint
    |> Repo.get_by!(id: id, user_id: user_id)
    |> Repo.preload([:condition, days: :meals])
    |> sort_tree()
  end

  # ── public / shared reads ────────────────────────────────────────────────────

  @doc """
  Fetches a **public** blueprint by its slug, with its full day/meal tree, owner
  and condition loaded — the read behind the public preview page. Raises
  `Ecto.NoResultsError` for a missing or private blueprint.
  """
  def get_public_blueprint_by_slug!(slug) do
    Blueprint
    |> Repo.get_by!(slug: slug, visibility: "public")
    |> Repo.preload([:condition, [user: :professional_profile], days: :meals])
    |> sort_tree()
  end

  @doc """
  Lists public blueprints newest-first for the browse grid, condition/owner
  preloaded and `plans_count` populated. Options: `:limit`, `:offset`.
  """
  def list_public_blueprints(opts \\ []) do
    Blueprint
    |> where([b], b.visibility == "public")
    |> order_by([b], desc: b.inserted_at)
    |> maybe_limit(opts)
    |> Repo.all()
    |> Repo.preload([:condition, user: :professional_profile])
    |> put_plans_count()
  end

  @doc """
  A user's **public** blueprints, newest-first, condition/owner + `plans_count`
  loaded — the "meal blueprints" section on their public nutritionist page.
  """
  def list_public_blueprints_for_user(user_id) do
    Blueprint
    |> where([b], b.visibility == "public" and b.user_id == ^user_id)
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
    |> Repo.preload([:condition, user: :professional_profile])
    |> put_plans_count()
  end

  @doc "Public blueprints whose name matches `term` (case-insensitive), newest first."
  def search_public_blueprints(term, opts \\ [])

  def search_public_blueprints(term, opts) when is_binary(term) do
    trimmed = String.trim(term)

    if trimmed == "" do
      list_public_blueprints(opts)
    else
      pattern = "%#{trimmed}%"

      Blueprint
      |> where([b], b.visibility == "public" and ilike(b.name, ^pattern))
      |> order_by([b], desc: b.inserted_at)
      |> maybe_limit(opts)
      |> Repo.all()
      |> Repo.preload([:condition, user: :professional_profile])
      |> put_plans_count()
    end
  end

  def search_public_blueprints(_term, opts), do: list_public_blueprints(opts)

  @doc """
  The completed generation runs attached to a **public** blueprint (for the
  preview page), each with its plan meals preloaded — not owner-scoped.
  """
  def list_public_plans_for_blueprint(blueprint_id) do
    plans =
      Repo.all(
        from(p in BlueprintPlan,
          where: p.blueprint_id == ^blueprint_id and p.status == "completed",
          order_by: [desc: p.inserted_at]
        )
      )

    Enum.map(plans, fn plan -> %{plan | meals: list_plan_meals(plan.id)} end)
  end

  @doc """
  Resolves a blueprint a `user_id` may **generate a personal plan from**: one they
  own, one they've saved, or any public blueprint. Loads the tree + condition.
  Raises `Ecto.NoResultsError` otherwise (e.g. a foreign private blueprint).
  """
  def get_blueprint_for_generation(user_id, id) do
    saved_ids = list_saved_blueprint_ids_for_user(user_id)

    Blueprint
    |> where([b], b.id == ^id)
    |> where([b], b.user_id == ^user_id or b.visibility == "public" or b.id in ^saved_ids)
    |> Repo.one!()
    |> Repo.preload([:condition, days: :meals])
    |> sort_tree()
  end

  defp maybe_limit(query, opts) do
    query
    |> then(fn q -> if l = opts[:limit], do: limit(q, ^l), else: q end)
    |> then(fn q -> if o = opts[:offset], do: offset(q, ^o), else: q end)
  end

  # Batch-count completed plans per blueprint and stamp the virtual field, so the
  # browse grid avoids an N+1.
  defp put_plans_count([]), do: []

  defp put_plans_count(blueprints) do
    ids = Enum.map(blueprints, & &1.id)

    counts =
      Repo.all(
        from(p in BlueprintPlan,
          where: p.blueprint_id in ^ids and p.status == "completed",
          group_by: p.blueprint_id,
          select: {p.blueprint_id, count(p.id)}
        )
      )
      |> Map.new()

    Enum.map(blueprints, fn b -> %{b | plans_count: Map.get(counts, b.id, 0)} end)
  end

  # ── saved blueprints (profile) ───────────────────────────────────────────────

  @doc "Saves a blueprint to a user's profile (idempotent on the unique index)."
  def save_blueprint_for_user(user_id, blueprint_id) do
    %UserBlueprint{}
    |> UserBlueprint.changeset(%{user_id: user_id, blueprint_id: blueprint_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc "Removes a saved blueprint from a user's profile."
  def remove_saved_blueprint_for_user(user_id, blueprint_id) do
    from(ub in UserBlueprint,
      where: ub.user_id == ^user_id and ub.blueprint_id == ^blueprint_id
    )
    |> Repo.delete_all()
  end

  @doc "A user's saved blueprints, newest-saved first, condition/owner + `plans_count` loaded."
  def list_saved_blueprints_for_user(user_id) do
    Repo.all(
      from(ub in UserBlueprint,
        where: ub.user_id == ^user_id,
        order_by: [desc: ub.inserted_at],
        join: b in assoc(ub, :blueprint),
        select: b
      )
    )
    |> Repo.preload([:condition, user: :professional_profile])
    |> put_plans_count()
  end

  @doc "The blueprint ids a user has saved."
  def list_saved_blueprint_ids_for_user(user_id) do
    Repo.all(from(ub in UserBlueprint, where: ub.user_id == ^user_id, select: ub.blueprint_id))
  end

  @doc "True if `user_id` has saved `blueprint_id`."
  def blueprint_saved?(user_id, blueprint_id) do
    Repo.exists?(
      from(ub in UserBlueprint,
        where: ub.user_id == ^user_id and ub.blueprint_id == ^blueprint_id
      )
    )
  end

  @doc """
  The bioactive-compound **names** a condition recommends, bucketed by direction
  (via `Health.CompoundRecommendation`) — used to auto-suggest day-level compounds
  when a blueprint's disease is selected. `encourage` → `:required`;
  `avoid`/`limit`/`caution` → `:avoid`; `monitor` is ignored. Returns
  `%{required: [], avoid: []}` for a nil id.
  """
  def recommended_compounds_for_condition(nil), do: %{required: [], avoid: []}

  def recommended_compounds_for_condition(condition_id) do
    condition_id
    |> Mehungry.Health.recommendations_for_condition()
    |> Enum.reduce(%{required: [], avoid: []}, fn rec, acc ->
      case rec.recommendation do
        "encourage" ->
          Map.update!(acc, :required, &(&1 ++ [rec.compound.name]))

        d when d in ["avoid", "limit", "caution"] ->
          Map.update!(acc, :avoid, &(&1 ++ [rec.compound.name]))

        _ ->
          acc
      end
    end)
    |> Map.new(fn {k, names} -> {k, Enum.uniq(names)} end)
  end

  @doc """
  The **nutrient names** a condition recommends, bucketed by direction (via
  `Health.NutrientRecommendation`) — the nutrient sibling of
  `recommended_compounds_for_condition/1`, used to auto-suggest the blueprint's
  `required_nutrients`/`avoid_nutrients` when a disease is selected. `encourage` →
  `:required`; `avoid`/`limit`/`caution` → `:avoid`; `monitor` ignored. Returns
  `%{required: [], avoid: []}` for a nil id.
  """
  def recommended_nutrients_for_condition(nil), do: %{required: [], avoid: []}

  def recommended_nutrients_for_condition(condition_id) do
    condition_id
    |> Mehungry.Health.nutrient_recommendations_for_condition()
    |> Enum.reduce(%{required: [], avoid: []}, fn rec, acc ->
      case rec.recommendation do
        "encourage" ->
          Map.update!(acc, :required, &(&1 ++ [rec.nutrient_name]))

        d when d in ["avoid", "limit", "caution"] ->
          Map.update!(acc, :avoid, &(&1 ++ [rec.nutrient_name]))

        _ ->
          acc
      end
    end)
    |> Map.new(fn {k, names} -> {k, Enum.uniq(names)} end)
  end

  @doc "Builds a `Blueprint` changeset."
  def change_blueprint(%Blueprint{} = blueprint, attrs \\ %{}) do
    Blueprint.changeset(blueprint, attrs)
  end

  @doc "Creates a blueprint from `attrs` (typically `default_blueprint_attrs/2`)."
  def create_blueprint(attrs) do
    %Blueprint{}
    |> Blueprint.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a blueprint (nested days/meals cast through the changeset)."
  def update_blueprint(%Blueprint{} = blueprint, attrs) do
    Mehungry.Repo.transact(fn repo ->
      changeset =
        blueprint
        |> Blueprint.changeset(attrs)

      case Repo.update(changeset) do
        {:ok, blueprint} ->
          blueprint = Repo.preload(blueprint, :plans)

          Enum.each(blueprint.plans, fn plan ->
            compatibility = plan_compatibility(plan.user_id, blueprint.id, plan.id)

            plan
            |> BlueprintPlan.changeset(%{compatibility: compatibility})
            |> Repo.update()
          end)

          {:ok, blueprint}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  @doc "Deletes a blueprint; child days/meals cascade at the DB level."
  def delete_blueprint(%Blueprint{} = blueprint) do
    Repo.delete(blueprint)
  end

  @doc """
  Deep-copies a blueprint (new rows throughout), defaulting the name to
  "Copy of <name>". Keeps the same owner unless overridden.
  """
  def duplicate_blueprint(%Blueprint{} = blueprint, overrides \\ %{}) do
    source = get_blueprint!(blueprint.user_id, blueprint.id)

    attrs = %{
      user_id: source.user_id,
      condition_id: source.condition_id,
      name: Map.get(overrides, :name, "Copy of #{source.name}"),
      description: source.description,
      required_nutrients: source.required_nutrients,
      avoid_nutrients: source.avoid_nutrients,
      required_compounds: source.required_compounds,
      avoid_compounds: source.avoid_compounds,
      preferred_foods: source.preferred_foods,
      days: Enum.map(source.days, &day_to_attrs/1)
    }

    create_blueprint(attrs)
  end

  @doc """
  Builds the canonical empty skeleton: exactly 7 days × one target row per
  `MealType.values/0`, ready to pass to `create_blueprint/1`. The single source
  of the 7×5 grid shape.
  """
  def default_blueprint_attrs(user_id, name) do
    %{
      user_id: user_id,
      name: name,
      required_nutrients: [],
      avoid_nutrients: [],
      required_compounds: [],
      avoid_compounds: [],
      preferred_foods: [],
      days:
        for day_index <- 1..7 do
          %{
            day_index: day_index,
            meals:
              for meal_type <- MealType.values() do
                %{meal_type: meal_type}
              end
          }
        end
    }
  end

  @doc """
  Serializes a loaded blueprint into a plain nested map of primitives, so the
  AI layer can read its targets without depending on the Ecto structs.
  """
  def to_targets_map(%Blueprint{} = blueprint) do
    blueprint = sort_tree(blueprint)

    %{
      name: blueprint.name,
      description: blueprint.description,
      condition: condition_name(blueprint),
      required_nutrients: blueprint.required_nutrients,
      avoid_nutrients: blueprint.avoid_nutrients,
      required_compounds: blueprint.required_compounds,
      avoid_compounds: blueprint.avoid_compounds,
      preferred_foods: blueprint.preferred_foods,
      days:
        Enum.map(blueprint.days, fn day ->
          %{
            day_index: day.day_index,
            total_calorie_target: day.total_calorie_target,
            meals:
              Enum.map(day.meals, fn meal ->
                %{
                  meal_type: meal.meal_type,
                  protein_pct: meal.protein_pct,
                  carbs_pct: meal.carbs_pct,
                  fats_pct: meal.fats_pct,
                  note: meal.note
                }
              end)
          }
        end)
    }
  end

  # ── generated plans ─────────────────────────────────────────────────────────

  @doc """
  A free-text preferences string distilled from a blueprint's targets, fed to
  the AI meal planner as the guiding brief (the planner reads free-text, not the
  structured tree yet).
  """
  def blueprint_preferences(%Blueprint{} = blueprint) do
    blueprint = Repo.preload(blueprint, :condition)

    [
      "Follow the meal blueprint \"#{blueprint.name}\".",
      blueprint.description,
      blueprint.condition && "Health condition to respect: #{blueprint.condition.name}.",
      tag_line("Prefer nutrients", blueprint.required_nutrients),
      tag_line("Avoid nutrients", blueprint.avoid_nutrients),
      tag_line("Prefer bioactive compounds", blueprint.required_compounds),
      tag_line("Avoid bioactive compounds", blueprint.avoid_compounds),
      tag_line("Preferred foods", blueprint.preferred_foods)
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
  end

  defp tag_line(_label, []), do: nil
  defp tag_line(_label, nil), do: nil
  defp tag_line(label, tags), do: "#{label}: #{Enum.join(tags, ", ")}."

  @doc "Records a new (in-flight) generation run for a blueprint."
  def create_plan(attrs) do
    %BlueprintPlan{}
    |> BlueprintPlan.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a generation-run row (status, meals_count, error)."
  def update_plan(%BlueprintPlan{} = plan, attrs) do
    Mehungry.Repo.transact(fn repo ->
      changeset =
        plan
        |> BlueprintPlan.changeset(attrs)

      case Repo.update(changeset) do
        {:ok, plan} ->
          compatibility = plan_compatibility(plan.user_id, plan.blueprint_id, plan.id)

          plan
          |> BlueprintPlan.changeset(%{compatibility: compatibility})
          |> Repo.update()

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  @doc "Deletes a generation-run row; its calendar meals stay (FK nilifies)."
  def delete_plan(%BlueprintPlan{} = plan), do: Repo.delete(plan)

  @doc "Owner-scoped fetch of a generation run."
  def get_plan!(user_id, id) do
    Repo.get_by!(BlueprintPlan, id: id, user_id: user_id)
  end

  @doc "Owner-scoped fetch of a generation run."
  def get_plan!(id) do
    Repo.get_by!(BlueprintPlan, id: id)
  end

  @doc """
  The generation runs for one blueprint, newest first, each with its
  (calendar-independent) plan meals preloaded and sorted by day + slot for the
  accordion. These are `BlueprintPlanMeal` rows — nothing on the calendar until
  the plan is imported.
  """
  def list_plans_for_blueprint(user_id, blueprint_id) do
    plans =
      Repo.all(
        from(p in BlueprintPlan,
          where: p.user_id == ^user_id and p.blueprint_id == ^blueprint_id,
          order_by: [desc: p.inserted_at]
        )
      )

    Enum.map(plans, fn plan -> %{plan | meals: list_plan_meals(plan.id)} end)
  end

  @doc "A plan's `BlueprintPlanMeal` rows, recipe + ingredient children loaded, day+slot ordered."
  def list_plan_meals(plan_id) do
    order = MealType.values() |> Enum.with_index() |> Map.new()

    Repo.all(
      from(m in BlueprintPlanMeal,
        where: m.blueprint_plan_id == ^plan_id,
        preload: [:recipe, ingredients: [:ingredient, :measurement_unit, :ingredient_portion]]
      )
    )
    |> Enum.sort_by(fn m -> {m.day_index, Map.get(order, m.meal_type, 99)} end)
  end

  @doc """
  Like `list_plan_meals/1` but with the deeper preload the compatibility analyzer
  needs — each recipe's `recipe_ingredients` (with their ingredient) so a meal's
  bioactive compounds can be resolved. Kept separate so the accordion's display
  query stays lightweight.
  """
  def list_plan_meals_with_ingredients(plan_id) do
    order = MealType.values() |> Enum.with_index() |> Map.new()

    Repo.all(
      from(m in BlueprintPlanMeal,
        where: m.blueprint_plan_id == ^plan_id,
        preload: [ingredients: :ingredient, recipe: [recipe_ingredients: :ingredient]]
      )
    )
    |> Enum.sort_by(fn m -> {m.day_index, Map.get(order, m.meal_type, 99)} end)
  end

  @doc """
  Analyzes a generated plan against its blueprint's targets, returning the
  per-meal / per-day compatibility report (see
  `Mehungry.MealBlueprints.PlanCompatibility`). `user_id`-scoped: the blueprint is
  loaded through `get_blueprint!/2`.
  """
  def plan_compatibility(user_id, blueprint_id, plan_id) do
    blueprint = get_blueprint!(user_id, blueprint_id)
    PlanCompatibility.analyze(blueprint, list_plan_meals_with_ingredients(plan_id))
  end

  @doc """
  Owner-scoped fetch of a single plan meal (joined through its plan's `user_id`),
  recipe/ingredient/unit preloaded. Raises if it belongs to another user.
  """
  def get_plan_meal!(user_id, plan_meal_id) do
    Repo.one!(
      from(m in BlueprintPlanMeal,
        join: p in assoc(m, :blueprint_plan),
        where: m.id == ^plan_meal_id and p.user_id == ^user_id,
        preload: [:recipe, ingredients: [:ingredient, :measurement_unit, :ingredient_portion]]
      )
    )
  end

  @doc "Builds a `BlueprintPlanMeal` changeset (for the plan-meal edit form)."
  def change_plan_meal(%BlueprintPlanMeal{} = plan_meal, attrs \\ %{}) do
    BlueprintPlanMeal.changeset(plan_meal, attrs)
  end

  @doc """
  Updates a generated plan meal — the nutritionist swapping a slot's recipe or
  ingredient / adjusting portions. `attrs` should set exactly one of the
  recipe/ingredient sides (the XOR is re-validated); clear the other side by
  passing `nil`.
  """
  def update_plan_meal(%BlueprintPlanMeal{} = plan_meal, attrs) do
    Mehungry.Repo.transact(fn repo ->
      result =
        plan_meal
        |> BlueprintPlanMeal.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, meal} ->
          plan = Mehungry.MealBlueprints.get_plan!(meal.blueprint_plan_id)

          # {:ok, plan} = Repo.update(changeset)
          compatibility = plan_compatibility(plan.user_id, plan.blueprint_id, plan.id)

          {:ok, plan} =
            plan
            |> BlueprintPlan.changeset(%{compatibility: compatibility})
            |> Repo.update()

          {:ok, {meal, plan}}

        {:error, err} ->
          {:error, err}
      end
    end)
  end

  @doc "Deletes a single plan meal (removes that slot from the generated plan)."
  def delete_plan_meal(%BlueprintPlanMeal{} = plan_meal), do: Repo.delete(plan_meal)

  @doc """
  Stores a generated plan's normalized entries (from
  `MealPlanGenerator.generate_entries/5`) as independent `BlueprintPlanMeal` rows
  and marks the plan completed. Does **not** touch the calendar.
  """
  def store_plan_meals(%BlueprintPlan{} = plan, entries) do
    Enum.each(entries, fn entry ->
      %BlueprintPlanMeal{}
      |> BlueprintPlanMeal.changeset(plan_meal_attrs(entry, plan.id))
      |> Repo.insert()
    end)

    update_plan(plan, %{status: "completed", meals_count: length(entries)})
  end

  # A generation entry is a recipe **or** a single ingredient; the ingredient is
  # stored as one `BlueprintPlanMealIngredient` child (a meal can later be edited
  # to hold a recipe plus several ingredients).
  defp plan_meal_attrs(entry, plan_id) do
    %{
      blueprint_plan_id: plan_id,
      day_index: entry.day_index,
      meal_type: entry.meal_type,
      recipe_id: entry.recipe_id,
      cooking_portions: entry.cooking_portions,
      ingredients: entry_ingredients(entry)
    }
  end

  defp entry_ingredients(%{ingredient_id: nil}), do: []

  defp entry_ingredients(%{ingredient_id: ingredient_id} = entry) do
    [
      %{
        ingredient_id: ingredient_id,
        quantity: entry.quantity,
        measurement_unit_id: entry.measurement_unit_id,
        ingredient_portion_id: entry.ingredient_portion_id
      }
    ]
  end

  defp entry_ingredients(_entry), do: []

  @doc "True once a plan has been imported to the calendar at least once."
  def plan_imported?(%BlueprintPlan{imported_at: imported_at}), do: not is_nil(imported_at)

  @doc """
  Materializes an (owner-scoped) plan onto the calendar starting at `start_date`:
  each `BlueprintPlanMeal` becomes a `History.UserMeal` (tagged with
  `blueprint_plan_id`) on `start_date + day_index - 1`.

  A plan always spans 7 days, so the whole `start_date..start_date + 6` week is
  **cleared first** — any existing meals in that span are deleted before the new
  plan is written (the plan overwrites the week rather than piling onto it).
  Re-import is allowed. Sets `imported_at`. Returns
  `{:ok, created_count, skipped_count, deleted_count}`.
  """
  def import_plan_to_calendar(user_id, %BlueprintPlan{} = plan, start_date) do
    end_date = Date.add(start_date, 6)
    deleted = Mehungry.History.delete_user_meals_in_date_range(user_id, start_date, end_date)

    results =
      plan.id
      |> list_plan_meals()
      |> Enum.map(&import_plan_meal(&1, user_id, plan.id, start_date))

    created = Enum.count(results, &match?({:ok, _}, &1))
    skipped = Enum.count(results, &match?({:error, _}, &1))

    update_plan(plan, %{imported_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})

    {:ok, created, skipped, deleted}
  end

  defp import_plan_meal(%BlueprintPlanMeal{} = m, user_id, plan_id, start_date) do
    date = Date.add(start_date, m.day_index - 1)
    dt = NaiveDateTime.new!(date, MealType.slot_time(m.meal_type))

    %{
      title: MealType.label(m.meal_type),
      meal_type: m.meal_type,
      start_dt: dt,
      user_id: user_id,
      blueprint_plan_id: plan_id
    }
    |> Map.merge(import_recipe_attrs(m))
    |> Map.merge(import_ingredient_attrs(m))
    |> Mehungry.History.create_user_meal()
  end

  defp import_recipe_attrs(%BlueprintPlanMeal{recipe_id: recipe_id} = m)
       when not is_nil(recipe_id) do
    %{
      recipe_user_meals: [
        %{
          recipe_id: recipe_id,
          cooking_portions: m.cooking_portions || 2,
          consume_portions: 1,
          cooking: true
        }
      ]
    }
  end

  defp import_recipe_attrs(_m), do: %{}

  defp import_ingredient_attrs(%BlueprintPlanMeal{ingredients: ingredients})
       when is_list(ingredients) and ingredients != [] do
    %{
      ingredient_user_meals:
        Enum.map(ingredients, fn ing ->
          %{
            ingredient_id: ing.ingredient_id,
            quantity: ing.quantity || 1.0,
            measurement_unit_id: ing.measurement_unit_id,
            ingredient_portion_id: ing.ingredient_portion_id
          }
        end)
    }
  end

  defp import_ingredient_attrs(_m), do: %{}

  # ── internal ────────────────────────────────────────────────────────────────

  # The condition name if it's loaded, else nil (the assoc may not be preloaded).
  defp condition_name(%Blueprint{condition: %{name: name}}), do: name
  defp condition_name(_), do: nil

  defp day_to_attrs(day) do
    %{
      day_index: day.day_index,
      total_calorie_target: day.total_calorie_target,
      meals: Enum.map(day.meals, &meal_to_attrs/1)
    }
  end

  defp meal_to_attrs(meal) do
    %{
      meal_type: meal.meal_type,
      protein_pct: meal.protein_pct,
      carbs_pct: meal.carbs_pct,
      fats_pct: meal.fats_pct,
      note: meal.note
    }
  end

  # Days come back ordered by day_index (schema preload_order); meals need
  # ordering by the canonical slot sequence in Elixir.
  defp sort_tree(%Blueprint{} = blueprint) do
    order = MealType.values() |> Enum.with_index() |> Map.new()

    days =
      blueprint.days
      |> Enum.sort_by(& &1.day_index)
      |> Enum.map(fn day ->
        %{day | meals: Enum.sort_by(day.meals, &Map.get(order, &1.meal_type, 99))}
      end)

    %{blueprint | days: days}
  end
end
