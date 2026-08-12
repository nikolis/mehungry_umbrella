defmodule Mehungry.Food.Measurements do
  @moduledoc """
  Measurement units, their translations, and ingredient portions
  (the ingredient ↔ measurement-unit bridge).
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Category,
    IngredientPortion,
    MeasurementUnit,
    MeasurementUnitTranslation,
    RecipeIngredient
  }

  alias Mehungry.Languages.Language

  # A name that is nothing but digits — the "unreconciled NDB/portion code"
  # marker. Defined at module top so both the numeric- and junk-name queries
  # (which appear above and below their own sections) can reference it.
  # (Postgres POSIX regex; anchored so "12 oz" etc. are excluded.)
  @numeric_name_fragment "^[0-9]+$"

  # The whitelist of genuine, food-agnostic measurement units. USDA's `measureUnit`
  # vocabulary mixes real units (cup, tablespoon, oz…) with food-specific
  # pseudo-units that carry normal ids (fruit, tomatoes, Banana, drumstick,
  # fillet…) and, on older imports, free-text portion labels landed here too.
  # Neither an id check (the pseudo-units aren't id 9999) nor a shape regex can
  # tell "cup" from "Banana", so this list is the single source of truth: a name
  # is a real unit iff it (case-insensitively) appears here. Used both to gate
  # unit *creation* in the USDA parser and to identify units to purge. Extend it
  # rather than loosening the check.
  @real_unit_names MapSet.new(
                     ~w(
                       g gram grams kg kilogram kilograms milligram milligrams mg
                       microgram micrograms mcg ng nanogram pg picogram
                       oz ounce ounces lb lbs pound pounds
                       l liter liters litre litres ml milliliter milliliters
                       dl deciliter cl centiliter
                       cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons
                       pint pints quart quarts gallon gallons
                       fluid_ounce
                       kcal kilocalorie kj kilojoule iu mg_ate
                       drop drops dash pinch scoop scoops
                       serving servings portion portions
                       piece pieces slice slices unit units item items each
                       wedge wedges stick sticks cube cubes ring rings strip strips
                       half halves sheet sheets tablet tablets
                       can cans container containers package packages packet packets
                       bottle bottles jar jars box boxes bag bags pouch pouches
                       carton cartons bowl bowls envelope envelopes
                     ) ++ ["fl oz", "international unit", "specific gravity", "µg"]
                   )

  @doc """
  Whether `name` is a genuine, food-agnostic measurement unit (case-insensitive).
  Everything else — food pseudo-units ("Banana", "tomatoes"), numeric codes,
  portion descriptions — is not a unit and should live on the portion, not in the
  units table.
  """
  def real_unit_name?(name) when is_binary(name) do
    MapSet.member?(@real_unit_names, name |> String.trim() |> String.downcase())
  end

  def real_unit_name?(_), do: false

  def get_measurement_unit!(nil), do: nil

  def get_measurement_unit!(id) do
    Repo.get(MeasurementUnit, id)
  end

  @doc """
  IngredientPortion represents the portions of ingredients and connects bassically ingredients with measurmenet Units
  """
  def get_measurement_unit_portions_for_ingredient(ingredient_id)
      when is_binary(ingredient_id) and ingredient_id == "" do
    []
  end

  def get_measurement_unit_portions_for_ingredient(ingredient_id) do
    from(ingp in Mehungry.Food.IngredientPortion, where: ingp.ingredient_id == ^ingredient_id)
    |> Repo.all()
    |> Repo.preload(:measurement_unit)
  end

  def get_measurement_unit_portions_for_ingredients(ingredient_ids)
      when is_list(ingredient_ids) do
    from(ingp in IngredientPortion, where: ingp.ingredient_id in ^ingredient_ids)
    |> Repo.all()
    |> Repo.preload(:measurement_unit)
    |> Enum.group_by(& &1.ingredient_id)
  end

  def get_measurement_unit_by_name(name) do
    from(mu in MeasurementUnit,
      where: mu.name == ^name or mu.alternate_name == ^name
    )
    |> Repo.all()
  end

  def create_measurement_unit(attrs, opts \\ []) do
    %MeasurementUnit{}
    |> MeasurementUnit.changeset(attrs)
    |> Repo.insert(opts)
  end

  def update_measurement_unit(%MeasurementUnit{} = measurement_unit, attrs \\ %{}) do
    measurement_unit
    |> MeasurementUnit.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a measurement unit. Returns `{:error, :referenced}` instead of
  raising when the unit is still referenced (by ingredients, ingredient
  portions, etc.) so callers can surface a friendly message.
  """
  def delete_measurement_unit(%MeasurementUnit{} = measurement_unit) do
    Repo.delete(measurement_unit)
  rescue
    Ecto.ConstraintError -> {:error, :referenced}
  end

  def change_measurement_unit(measurement_unit, attrs \\ %{}) do
    MeasurementUnit.changeset(measurement_unit, attrs)
  end

  @doc """
  Deletes every measurement unit with the given name **only if nothing
  references it**. Used to clean up the bogus units that older imports minted
  from free-text/numeric portion labels (e.g. "60919", "cake square (average
  weight of whole item)") once the portions that referenced them have been
  rebuilt without a unit.

  Runs the delete outside any surrounding transaction is the caller's
  responsibility — a foreign-key violation here raises `Ecto.ConstraintError`,
  which we rescue and treat as "still referenced, skip". Inside a transaction
  that rescue would be useless (the transaction is already aborted), so callers
  must invoke this after their insert transaction has committed.

  Returns the number of units actually deleted.
  """
  def delete_measurement_unit_if_unreferenced(name) when is_binary(name) do
    from(mu in MeasurementUnit, where: mu.name == ^name)
    |> Repo.all()
    |> Enum.reduce(0, fn unit, deleted ->
      try do
        Repo.delete!(unit)
        deleted + 1
      rescue
        Ecto.ConstraintError -> deleted
      end
    end)
  end

  def delete_measurement_unit_if_unreferenced(_), do: 0

  @doc """
  Force-purges every measurement unit with the given (junk) name, deleting
  everything that keeps it alive rather than skipping when referenced:

    * ingredient portions are **reconciled** — their `measurement_unit_id` is
      nulled so the portion row survives (it keeps its `description`), and
    * any `recipe_ingredient` pointing at the unit takes its **whole recipe**
      down with it (full dependent cascade via `Recipes.delete_recipes_by_ids/1`),
    * the unit's own translations are removed,
    * then the unit itself is deleted.

  Each unit is purged in its own transaction; if some *other* table still
  references it (e.g. a nutrient — never the case for numeric/free-text junk),
  the delete raises, the transaction rolls back, and that one unit is skipped
  with a warning instead of crashing the caller. Must run outside a surrounding
  transaction. Returns `%{units:, recipes:, portions:}` tallies.
  """
  def purge_junk_measurement_unit(name) when is_binary(name) do
    from(mu in MeasurementUnit, where: mu.name == ^name)
    |> Repo.all()
    |> Enum.reduce(%{units: 0, recipes: 0, portions: 0}, fn unit, acc ->
      case purge_unit(unit) do
        {:ok, %{recipes: r, portions: p}} ->
          %{units: acc.units + 1, recipes: acc.recipes + r, portions: acc.portions + p}

        _ ->
          acc
      end
    end)
  end

  def purge_junk_measurement_unit(_), do: %{units: 0, recipes: 0, portions: 0}

  # Junk = any measurement unit whose name is NOT a genuine unit (see
  # @real_unit_names). This catches everything at once: numeric codes ("60919"),
  # portion descriptions ("cake square (...)", "pint as purchased, yields"), and
  # USDA food pseudo-units that ship with real ids ("Banana", "tomatoes",
  # "fruit", "drumstick"). Comparison is case-insensitive and trims whitespace.
  defp junk_named_query do
    whitelist = MapSet.to_list(@real_unit_names)

    from(mu in MeasurementUnit,
      where: fragment("lower(btrim(?))", mu.name) not in ^whitelist
    )
  end

  @doc "Count of junk-named measurement units currently in the table."
  def count_junk_measurement_units do
    Repo.aggregate(junk_named_query(), :count, :id)
  end

  @doc "Preview list (limited) of junk-named units for the admin UI."
  def list_junk_measurement_units(limit \\ 50) do
    junk_named_query()
    |> order_by([mu], asc: mu.name)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Force-purges **every** junk-named measurement unit in the table (independent of
  any USDA reparse): each is removed via the same cascade as
  `purge_junk_measurement_unit/1` — dependent recipes deleted, portions reconciled
  to no unit, then the unit deleted. Must run outside a transaction. Returns
  `%{units:, recipes:, portions:}` tallies.
  """
  def purge_all_junk_measurement_units do
    junk_named_query()
    |> Repo.all()
    |> Enum.reduce(%{units: 0, recipes: 0, portions: 0}, fn unit, acc ->
      case purge_unit(unit) do
        {:ok, %{recipes: r, portions: p}} ->
          %{units: acc.units + 1, recipes: acc.recipes + r, portions: acc.portions + p}

        _ ->
          acc
      end
    end)
  end

  defp purge_unit(%MeasurementUnit{id: uid} = unit) do
    Repo.transaction(fn ->
      recipe_ids =
        from(ri in RecipeIngredient,
          where: ri.measurement_unit_id == ^uid,
          select: ri.recipe_id,
          distinct: true
        )
        |> Repo.all()

      {:ok, recipes_deleted} = Mehungry.Food.Recipes.delete_recipes_by_ids(recipe_ids)

      {portions_reconciled, _} =
        from(p in IngredientPortion, where: p.measurement_unit_id == ^uid)
        |> Repo.update_all(set: [measurement_unit_id: nil])

      from(t in MeasurementUnitTranslation, where: t.measurement_unit_id == ^uid)
      |> Repo.delete_all()

      Repo.delete!(unit)
      %{recipes: recipes_deleted, portions: portions_reconciled}
    end)
  rescue
    e ->
      Logger.warning(
        "[Measurements] could not purge junk unit #{inspect(unit.name)} (#{unit.id}): " <>
          Exception.message(e)
      )

      {:error, e}
  end

  @doc """
  Best-effort sweep that removes measurement units whose name is a bare number
  (unreconciled USDA NDB/portion codes) when nothing references them anymore.
  Complements the per-file cleanup for numeric junk left behind by older imports.
  Must run outside a transaction (see `delete_measurement_unit_if_unreferenced/1`).
  Returns the number of units deleted.
  """
  def delete_numeric_named_measurement_units do
    numeric_named_query()
    |> Repo.all()
    |> Enum.reduce(0, fn unit, deleted ->
      try do
        Repo.delete!(unit)
        deleted + 1
      rescue
        Ecto.ConstraintError -> deleted
      end
    end)
  end

  def list_measurement_units() do
    Repo.all(MeasurementUnit)
  end

  # ── Numeric-name reconciliation ────────────────────────────────────────────
  #
  # Some units were seeded with a bare USDA NDB number as their name (e.g.
  # "10205"). These helpers find them, and `reconcile_measurement_unit/2` swaps
  # the numeric name for the real USDA food description while preserving the code
  # in `ndb_number`.

  @doc "Whether `name` is a bare NDB number still awaiting reconciliation."
  def numeric_measurement_unit_name?(name) when is_binary(name),
    do: Regex.match?(~r/\A[0-9]+\z/, name)

  def numeric_measurement_unit_name?(_), do: false

  @doc "IDs of all measurement units whose name is a bare number."
  def list_numeric_named_measurement_unit_ids do
    numeric_named_query()
    |> select([mu], mu.id)
    |> Repo.all()
  end

  @doc "Count of measurement units whose name is a bare number."
  def count_numeric_named_measurement_units do
    numeric_named_query()
    |> Repo.aggregate(:count, :id)
  end

  @doc "Preview list (limited) of numeric-named measurement units for the admin UI."
  def list_numeric_named_measurement_units(limit \\ 50) do
    numeric_named_query()
    |> order_by([mu], asc: mu.name)
    |> limit(^limit)
    |> Repo.all()
  end

  defp numeric_named_query do
    from(mu in MeasurementUnit, where: fragment("? ~ ?", mu.name, @numeric_name_fragment))
  end

  @doc """
  Reconciles a numeric-named unit: stores the current numeric name as
  `ndb_number` and replaces `name` with the resolved USDA `resolved_name`. If a
  different unit already owns that name (unique constraint), the name is
  disambiguated with the NDB number rather than failing the whole run.
  """
  def reconcile_measurement_unit(%MeasurementUnit{} = unit, resolved_name)
      when is_binary(resolved_name) do
    ndb = unit.name
    resolved_name = String.trim(resolved_name)

    case update_measurement_unit(unit, %{name: resolved_name, ndb_number: ndb}) do
      {:ok, updated} ->
        {:ok, updated}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :name) do
          # Name already taken by another unit — keep it unique + non-numeric so
          # it drops off the reconciliation list, and still record the NDB number.
          update_measurement_unit(unit, %{
            name: "#{resolved_name} (NDB #{ndb})",
            ndb_number: ndb
          })
        else
          error
        end
    end
  end

  @doc """
  Recompute-all entry point: opens a `MeasurementUnitReconciliationRun` and
  enqueues one `MeasurementUnitReconciliationWorker` per numeric-named unit
  (each carrying the `run_id`). Returns the run.
  """
  def start_reconciliation_run do
    ids = list_numeric_named_measurement_unit_ids()
    run = Mehungry.Food.MeasurementUnitReconciliationRuns.start_run(length(ids))

    Enum.each(ids, fn id ->
      %{measurement_unit_id: id, run_id: run.id}
      |> Mehungry.ObanWorkers.MeasurementUnitReconciliationWorker.new()
      |> Oban.insert()
    end)

    run
  end

  def search_measurement_unit(term) do
    query =
      from mu in MeasurementUnit,
        where: ilike(mu.name, ^term)

    Repo.all(query)
  end

  def search_measurement_unit(search_term, language_str) do
    search_term = search_term <> "%"
    language = Repo.get_by(Language, name: language_str)

    Logger.info(
      "Searching for measurement unit with name: " <>
        search_term <>
        ", in: " <> language_str <> ", Identified as: #{inspect(language)}"
    )

    if is_nil(language) do
      query =
        from mu in MeasurementUnit,
          where: ilike(mu.name, ^search_term)

      Repo.all(query)
    else
      query =
        from mu_trans in MeasurementUnitTranslation,
          where: mu_trans.language_name == ^language.name

      query_search =
        from transl in query,
          where: ilike(transl.name, ^search_term)

      query_aggrigate =
        from tra in query_search,
          join: ing in MeasurementUnit,
          on: true,
          where: ing.id == tra.id,
          join: cat in Category,
          on: true,
          select: %MeasurementUnit{name: tra.name, id: ing.id}

      result = Repo.all(query_aggrigate)
      Logger.info("Search: " <> search_term <> " resulted: " <> inspect(result))
      result
    end
  end
end
