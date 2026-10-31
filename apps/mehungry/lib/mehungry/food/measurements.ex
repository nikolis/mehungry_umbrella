defmodule Mehungry.Food.Measurements do
  @moduledoc """
  Measurement units, their translations, and ingredient portions
  (the ingredient ↔ measurement-unit bridge).
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo
  alias Mehungry.ReferenceCache

  # Cache key for the user-independent `list_measurement_units/0` read.
  @units_cache_key :measurement_units

  alias Mehungry.Food.{
    Category,
    Ingredient,
    IngredientPortion,
    MeasurementUnit,
    MeasurementUnitTranslation,
    PortionConversion,
    RecipeIngredient
  }

  alias Mehungry.Food.IngredientPortionGenerationRuns
  alias Mehungry.Food.Localization
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
  @real_unit_names MapSet.new(~w(
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
                     ) ++ ["fl oz", "international unit", "specific gravity", "µg"])

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

  @doc """
  The unit/portion options to offer for logging an ingredient — the single
  source of truth behind both the calendar meal form's unit dropdown and the
  `/api/v1/ingredients/search?source=local` response, so the mobile client
  builds `IngredientUserMeal`s exactly the way the LiveView does.

  Each option is a map:

      %{unit_selection: integer, measurement_unit_id: id | nil,
        ingredient_portion_id: id | nil, label: string}

  `unit_selection` is the signed picker encoding shared with `RecipeIngredient`
  / `IngredientUserMeal`: **positive** → a real `measurement_unit_id`
  (grams or a unit-bearing portion), **negative** → `-ingredient_portion_id`
  for a description-only portion (e.g. "1 medium banana"). "gram" is always
  appended so a portion-less ingredient stays usable.
  """
  def ingredient_unit_options(nil), do: gram_unit_options()

  def ingredient_unit_options(ingredient_id) do
    ingredient_id
    |> get_measurement_unit_portions_for_ingredient()
    |> build_unit_options()
  end

  @doc """
  Locale-aware `ingredient_unit_options/1`: overlays each unit-less portion's
  translated free-text description (from `Food.Localization.portion_display_names/2`)
  onto its option label, so the calendar meal form and the mobile ingredient
  search surface localized portion labels. `nil` locale / source locale behave
  like `ingredient_unit_options/1`.
  """
  def ingredient_unit_options(nil, locale), do: build_unit_options([], locale)

  def ingredient_unit_options(ingredient_id, locale) do
    ingredient_id
    |> get_measurement_unit_portions_for_ingredient()
    |> build_unit_options(locale)
  end

  @doc """
  `ingredient_unit_options/1` for an already-loaded list of portions (lets
  callers batch the portion query across many ingredients, then build each
  ingredient's options without re-querying).
  """
  def build_unit_options(portions) when is_list(portions) do
    Enum.map(portions, &portion_unit_option/1) ++ gram_unit_options()
  end

  @doc """
  `build_unit_options/1` with localized labels for `locale`. A unit-bearing
  portion (and the always-appended "gram") takes its translated
  **measurement-unit** name (`Food.Localization.unit_display_names/2`); a
  unit-less portion takes its translated free-text **description**
  (`portion_display_names/2`). Either falls back to its stored English label when
  no translation exists.
  """
  def build_unit_options(portions, locale) when is_list(portions) do
    grams = get_measurement_unit_by_name("gram")

    unit_ids =
      (Enum.map(portions, & &1.measurement_unit_id) ++ Enum.map(grams, & &1.id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    unit_names = Localization.unit_display_names(unit_ids, locale)

    descrs =
      portions
      |> Enum.reject(& &1.measurement_unit_id)
      |> Enum.map(& &1.id)
      |> Localization.portion_display_names(locale)

    Enum.map(portions, &portion_unit_option(&1, unit_names, descrs)) ++
      gram_unit_options(grams, unit_names)
  end

  @doc "The grams-family unit option(s), in `ingredient_unit_options/1` shape."
  def gram_unit_options do
    gram_unit_options(get_measurement_unit_by_name("gram"), %{})
  end

  defp gram_unit_options(grams, unit_names) do
    Enum.map(grams, fn mu ->
      %{
        unit_selection: mu.id,
        measurement_unit_id: mu.id,
        ingredient_portion_id: nil,
        label: Map.get(unit_names, mu.id, mu.name)
      }
    end)
  end

  # A portion with a real measurement unit encodes as the positive unit id; a
  # description-only portion (no unit) encodes as `-portion_id`.
  defp portion_unit_option(%IngredientPortion{measurement_unit_id: mu_id} = portion)
       when not is_nil(mu_id) do
    %{
      unit_selection: mu_id,
      measurement_unit_id: mu_id,
      ingredient_portion_id: nil,
      label: IngredientPortion.display_name(portion) || "portion"
    }
  end

  defp portion_unit_option(%IngredientPortion{} = portion) do
    %{
      unit_selection: -portion.id,
      measurement_unit_id: nil,
      ingredient_portion_id: portion.id,
      label: IngredientPortion.display_name(portion) || "portion"
    }
  end

  # Locale-aware variants: a unit-bearing portion takes its translated
  # measurement-unit name when one exists (falling back to the English
  # unit-derived label); a unit-less portion takes its translated free-text
  # description when one exists.
  defp portion_unit_option(%IngredientPortion{measurement_unit_id: mu_id} = portion, unit_names, _descrs)
       when not is_nil(mu_id) do
    label = Map.get(unit_names, mu_id) || IngredientPortion.display_name(portion) || "portion"

    %{
      unit_selection: mu_id,
      measurement_unit_id: mu_id,
      ingredient_portion_id: nil,
      label: label
    }
  end

  defp portion_unit_option(%IngredientPortion{} = portion, _unit_names, descrs) do
    # The translated description is a raw label ("1 φλιτζάνι"); strip its
    # quantity the same way `display_name/1` does for the untranslated path.
    label =
      case Map.get(descrs, portion.id) do
        nil -> IngredientPortion.display_name(portion) || "portion"
        desc -> IngredientPortion.strip_amount(desc)
      end

    %{
      unit_selection: -portion.id,
      measurement_unit_id: nil,
      ingredient_portion_id: portion.id,
      label: label
    }
  end

  def create_measurement_unit(attrs, opts \\ []) do
    %MeasurementUnit{}
    |> MeasurementUnit.changeset(attrs)
    |> Repo.insert(opts)
    |> tap_invalidate_units()
  end

  def update_measurement_unit(%MeasurementUnit{} = measurement_unit, attrs \\ %{}) do
    measurement_unit
    |> MeasurementUnit.changeset(attrs)
    |> Repo.update()
    |> tap_invalidate_units()
  end

  # Drop the cached unit list after a write. Takes the `{:ok, _} | {:error, _}`
  # Repo result through untouched so it composes in the pipeline.
  defp tap_invalidate_units({:ok, _} = result) do
    ReferenceCache.invalidate(@units_cache_key)
    result
  end

  defp tap_invalidate_units(other), do: other

  @doc """
  Deletes a measurement unit. Returns `{:error, :referenced}` instead of
  raising when the unit is still referenced (by ingredients, ingredient
  portions, etc.) so callers can surface a friendly message.
  """
  def delete_measurement_unit(%MeasurementUnit{} = measurement_unit) do
    measurement_unit
    |> Repo.delete()
    |> tap_invalidate_units()
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
    deleted =
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

    if deleted > 0, do: ReferenceCache.invalidate(@units_cache_key)
    deleted
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
    tally =
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

    if tally.units > 0, do: ReferenceCache.invalidate(@units_cache_key)
    tally
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
    ReferenceCache.fetch(@units_cache_key, fn -> Repo.all(MeasurementUnit) end)
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

  # ── Derived-portion generation ─────────────────────────────────────────────
  #
  # Materializes the metric + common-recipe portions a user would want to log an
  # ingredient with (see `Mehungry.Food.PortionConversion`): mass units from an
  # ingredient-independent constant, volume units from the ingredient's density
  # (derived from any one existing volume portion). Idempotent — a target portion
  # that already exists is left untouched — so the whole sweep is re-runnable.

  @doc """
  Creates the missing derived portions (`PortionConversion.target_mass/0` +
  `target_volume/0`) for one ingredient and returns the number of new
  `IngredientPortion` rows created. Mass portions always synthesize; volume
  portions only when the ingredient has a volume portion to anchor density on
  (otherwise they are skipped). Safe to call repeatedly.
  """
  def generate_portions_for_ingredient(ingredient_id) do
    mass_created =
      Enum.reduce(PortionConversion.target_mass(), 0, fn token, acc ->
        acc + ensure_derived_portion(ingredient_id, token, PortionConversion.mass_grams_per_unit(token))
      end)

    volume_created =
      case PortionConversion.grams_per_ml(ingredient_id) do
        :none ->
          0

        {:ok, grams_per_ml} ->
          Enum.reduce(PortionConversion.target_volume(), 0, fn token, acc ->
            gram_weight = grams_per_ml * PortionConversion.volume_ml_per_unit(token)
            acc + ensure_derived_portion(ingredient_id, token, gram_weight)
          end)
      end

    mass_created + volume_created
  end

  # Creates a `(ingredient, target-unit)` portion at `amount: 1.0` unless one
  # already exists. Returns 1 if created, 0 if skipped or on a bad gram weight.
  defp ensure_derived_portion(_ingredient_id, _token, gram_weight)
       when not is_number(gram_weight) or gram_weight <= 0.0,
       do: 0

  defp ensure_derived_portion(ingredient_id, token, gram_weight) do
    unit = resolve_target_unit(token)

    cond do
      is_nil(unit) ->
        0

      derived_portion_exists?(ingredient_id, unit.id) ->
        0

      true ->
        {:ok, _} =
          %IngredientPortion{}
          |> IngredientPortion.changeset(%{
            ingredient_id: ingredient_id,
            measurement_unit_id: unit.id,
            gram_weight: gram_weight,
            amount: 1.0
          })
          |> Repo.insert()

        1
    end
  end

  defp derived_portion_exists?(ingredient_id, unit_id) do
    from(ip in IngredientPortion,
      where: ip.ingredient_id == ^ingredient_id and ip.measurement_unit_id == ^unit_id
    )
    |> Repo.exists?()
  end

  # Finds the single canonical `MeasurementUnit` for a target token, reusing any
  # existing row whose name is an alias spelling (so "teaspoon"/"l" are reused
  # rather than minting "tsp"/"liter" duplicates); mints the canonical name only
  # when none exists. Lowest id wins so the choice is stable across runs.
  defp resolve_target_unit(token) do
    names = PortionConversion.alias_names_for(token)

    existing =
      from(mu in MeasurementUnit,
        where: fragment("lower(btrim(?))", mu.name) in ^names,
        order_by: [asc: mu.id],
        limit: 1
      )
      |> Repo.one()

    case existing do
      %MeasurementUnit{} = unit ->
        unit

      nil ->
        case create_measurement_unit(%{name: token}) do
          {:ok, unit} -> unit
          # Lost a race / name taken — re-fetch the canonical row.
          {:error, _} -> Repo.get_by(MeasurementUnit, name: token)
        end
    end
  end

  @doc """
  Opens an `IngredientPortionGenerationRun` and enqueues one
  `IngredientPortionGenerationWorker` per ingredient (each carrying the
  `run_id`). Returns the run.
  """
  def start_ingredient_portion_generation_run do
    ids = from(i in Ingredient, select: i.id) |> Repo.all()
    run = IngredientPortionGenerationRuns.start_run(length(ids))

    Enum.each(ids, fn id ->
      %{ingredient_id: id, run_id: run.id}
      |> Mehungry.ObanWorkers.IngredientPortionGenerationWorker.new()
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
