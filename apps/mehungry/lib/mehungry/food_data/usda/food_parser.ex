defmodule Mehungry.FoodData.Usda.FoodParser do
  @moduledoc """
  This module is responsible for parsing food and nutrition related data gotten from Food Data Central and translate them into a form that fits the database model goten from  https://www.usda.gov/
  """

  import Ecto.Query, warn: false

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientNutrient, IngredientPortion}
  alias Mehungry.Repo

  require Logger

  @measurement_unit_dict [
    {"gram", "g"},
    {"gigatonne", "Gt"},
    {"milligram", "mg"},
    {"microgram", "µg"},
    {"nanogram", "ng"},
    {"picogram", "pg"},
    {"picogram", "pg"},
    {"kilocalorie", "kcal"},
    {"kilojoule", "kJ"},
    {"International Unit", "IU"},
    {"Specific gravity", "sp gr"}
  ]

  # Ingest a single FDC-format food: upsert the ingredient, then create (new row)
  # or replace (existing row) its portions and nutrients. Returns the result of
  # the child inserts on success or "" on a failed ingredient changeset — callers
  # don't use the return value.
  def create_ingredient(attrs, nutrient_data_source \\ nil) do
    food_portions = attrs["foodPortions"]
    food_nutrients = attrs["foodNutrients"]
    ingredient_attrs = build_ingredient_attrs(attrs, nutrient_data_source)

    # A food with no description has no name — the natural key we upsert on.
    # Skip it (rather than letting get_ingredient_by_name(nil) raise) so one
    # incomplete record can't roll back the whole file's transaction.
    if blank_name?(ingredient_attrs.name) do
      Logger.warning(
        "[FoodData.Usda.FoodParser] skipping food with no description (fdcId=#{inspect(attrs["fdcId"])})"
      )

      :skipped
    else
      upsert_and_persist(ingredient_attrs, food_portions, food_nutrients)
    end
  end

  defp blank_name?(nil), do: true
  defp blank_name?(name) when is_binary(name), do: String.trim(name) == ""
  defp blank_name?(_), do: false

  defp upsert_and_persist(ingredient_attrs, food_portions, food_nutrients) do
    case upsert_ingredient(ingredient_attrs) do
      {:ok, ingredient, "created"} ->
        Logger.info("#{ingredient.name} was created successfully")

        if not is_nil(food_portions) do
          create_ingredient_portions(food_portions, ingredient)
        end

        Enum.each(food_nutrients, fn nutrient -> get_or_create_nutrient(ingredient, nutrient) end)

      {:ok, ingredient, "updated"} ->
        Logger.info("#{ingredient.name} was updated successfully")

        # Re-seeding an existing ingredient: replace its portions/nutrients instead
        # of appending a second set, reusing the same delete-then-recreate helper as
        # the reconciliation path (which also guards against wiping on empty FDC data).
        replace_portions_and_nutrients(ingredient, food_portions || [], food_nutrients || [])

      {:error, changeset} ->
        Logger.error(
          "[FoodData.Usda.FoodParser] Failed to create ingredient: #{inspect(changeset.errors)}"
        )

        ""
    end
  end

  @doc """
  Corrects an *existing* ingredient in place from freshly-fetched FDC data,
  keyed on the row's `fdc_id` rather than upserting by name.

  Used by `Mehungry.ObanWorkers.IngredientReconciliationWorker` to verify and
  repair stored ingredient data against the authoritative USDA record. Differs
  from `create_ingredient/2` in three ways:

    * it updates the *given* row, so a drifted USDA description can never spawn
      a duplicate ingredient;
    * it never rewrites `name` (to avoid breaking slugs/translations or
      colliding with another row's unique name) — only the nutritional payload
      and USDA metadata are corrected;
    * it *replaces* portions and nutrients (delete-then-recreate) so stale rows
      don't accumulate across passes.

  Runs in a transaction; returns `{:ok, ingredient}` or `{:error, reason}`.
  """
  def reconcile_ingredient(%Ingredient{} = ingredient, attrs) do
    food_portions = attrs["foodPortions"] || []
    food_nutrients = attrs["foodNutrients"] || []

    # Drop :name (never renamed here) and any nil values so a sparse FDC record
    # can't blank out good data we already hold (e.g. an existing category).
    update_attrs =
      attrs
      |> build_ingredient_attrs(ingredient.nutrient_data_source)
      |> Map.delete(:name)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Repo.transaction(fn ->
      case Food.update_ingredient(ingredient, update_attrs) do
        {:ok, updated} ->
          replace_portions_and_nutrients(updated, food_portions, food_nutrients)
          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Wipe the ingredient's current portions/nutrients and rebuild them from the
  # FDC payload, reusing the same create paths as a fresh import.
  #
  # Each list is only replaced when the FDC record actually carries data for it:
  # a sparse USDA record with an empty `foodPortions`/`foodNutrients` must not
  # delete-then-recreate into nothing, wiping good rows we already hold. This
  # mirrors the nil-rejection guarding the scalar fields in `reconcile_ingredient/2`.
  defp replace_portions_and_nutrients(ingredient, food_portions, food_nutrients) do
    unless food_portions == [] do
      Repo.delete_all(from(p in IngredientPortion, where: p.ingredient_id == ^ingredient.id))
      create_ingredient_portions(food_portions, ingredient)
    end

    unless food_nutrients == [] do
      Repo.delete_all(from(n in IngredientNutrient, where: n.ingredient_id == ^ingredient.id))
      Enum.each(food_nutrients, fn nutrient -> get_or_create_nutrient(ingredient, nutrient) end)
    end
  end

  # Insert a new ingredient or update the existing one with the same name. The
  # `action` word ("created"/"updated") is threaded back out purely for logging.
  defp upsert_ingredient(attrs) do
    case Food.get_ingredient_by_name(attrs.name) do
      nil ->
        with {:ok, ingredient} <- Food.create_ingredient(attrs), do: {:ok, ingredient, "created"}

      existing ->
        with {:ok, ingredient} <- Food.update_ingredient(existing, attrs),
             do: {:ok, ingredient, "updated"}
    end
  end

  defp build_ingredient_attrs(attrs, nutrient_data_source) do
    category = get_or_create_food_category(category_description(attrs), category_usda_code(attrs))

    %{
      name: attrs["description"],
      # Prefer FDC's dataType (Foundation/SR Legacy/Branded/Survey) which is the
      # dataset the admin food-class filter expects; fall back to foodClass
      # (usually "FinalFood") for AI-generated or legacy records without a dataType.
      food_class: attrs["dataType"] || attrs["foodClass"],
      # Keep the new structured columns consistent with food_class on import so
      # freshly-created rows don't need a reconciliation pass to be corrected.
      data_type: attrs["dataType"],
      fdc_id: attrs["fdcId"],
      ndb_number: attrs["ndbNumber"],
      nutrient_conversion_factors: attrs["nutrientConversionFactors"],
      publication_date: attrs["publicationDate"],
      category_id: category && category.id,
      nutrient_data_source: nutrient_data_source
    }
  end

  # FDC exposes the food's category under one of three keys depending on dataset;
  # use the first one present.
  defp category_description(attrs) do
    attrs["foodCategory"]["description"] ||
      attrs["wweiaFoodCategory"]["wweiaFoodCategoryDescription"] ||
      attrs["brandedFoodCategory"]
  end

  # FDC exposes the category's USDA code under one of two keys depending on
  # dataset; use the first present and stringify it.
  defp category_usda_code(attrs) do
    case attrs["foodCategory"]["code"] || attrs["wweiaFoodCategory"]["wweiaFoodCategoryCode"] do
      nil -> nil
      code -> to_string(code)
    end
  end

  defp get_or_create_food_category(nil, _usda_code), do: nil

  defp get_or_create_food_category(category_name, usda_code) do
    case Food.get_category_by_name(category_name) do
      nil ->
        {:ok, category} = Food.create_category(%{name: category_name, usda_code: usda_code})
        category

      %{usda_code: nil} = category when not is_nil(usda_code) ->
        {:ok, category} = Food.update_category(category, %{usda_code: usda_code})
        category

      category ->
        category
    end
  end

  # --- Portions -------------------------------------------------------------

  defp create_ingredient_portions(food_portions, ingredient) do
    Enum.each(food_portions, fn portion ->
      measurement_unit = resolve_portion_unit(portion, ingredient)

      # With a real unit, keep only USDA's `portionDescription` as extra detail
      # (a bare modifier like "sliced" shouldn't shadow the unit name at display
      # time). Without a unit, fall back through the full label chain so the
      # portion still carries a name.
      description =
        if measurement_unit do
          normalize_unit_name(portion["portionDescription"])
        else
          portion_description(portion)
        end

      # A portion with neither a real unit nor a description carries no usable
      # label; skip it rather than inserting an empty row.
      if is_nil(measurement_unit) and is_nil(description) do
        :skip
      else
        Food.create_ingredient_portion(%{
          amount: portion["amount"],
          value: portion["value"],
          gram_weight: portion["gramWeight"],
          reference_id: portion["id"],
          min_year_acquired: portion["minYearAcquired"],
          sequence_number: portion["sequenceNumber"],
          ingredient_id: ingredient.id,
          measurement_unit_id: measurement_unit && measurement_unit.id,
          description: description
        })
      end
    end)
  end

  # A portion gets a measurement unit ONLY when its `measureUnit.name` is a
  # genuine unit (Food.real_unit_name?/1). USDA's measureUnit vocabulary also
  # contains food-specific pseudo-units with normal ids ("Banana", "tomatoes",
  # "fruit", "drumstick") and, historically, free text landed here too — none of
  # those belong in the units table, so they resolve to nil and their label is
  # kept on the portion's `description` instead. Undetermined (id 9999) also → nil.
  defp resolve_portion_unit(portion, ingredient) do
    case measure_unit_name(portion) do
      nil -> nil
      name -> if Food.real_unit_name?(name), do: get_or_create_measurement_unit(name, ingredient)
    end
  end

  # The `measureUnit.name` when it is a usable label (not undetermined/blank),
  # else nil. Shared by unit resolution, the description fallback, and cleanup.
  defp measure_unit_name(portion) do
    case portion["measureUnit"] do
      %{"id" => 9999} ->
        nil

      %{"name" => name} when is_binary(name) ->
        case normalize_unit_name(name) do
          "undetermined" -> nil
          other -> other
        end

      _ ->
        nil
    end
  end

  # Human-readable portion label: USDA `portionDescription`, then `modifier`, then
  # the measureUnit label itself (so a food pseudo-unit like "tomatoes" that we
  # refused to mint as a unit still survives as the portion's description).
  # Blank/missing everywhere → nil.
  defp portion_description(portion) do
    normalize_unit_name(portion["portionDescription"]) ||
      normalize_unit_name(portion["modifier"]) ||
      measure_unit_name(portion)
  end

  # --- Junk-unit cleanup ----------------------------------------------------

  # For every portion in the reparsed batch, collect the unit names an import
  # (old or new) could have minted — from both `measureUnit.name` and the
  # canonical `modifier` — and purge the ones that are NOT genuine units. That
  # sweeps numeric codes ("60919"), free-text descriptions, and USDA food
  # pseudo-units ("Banana", "tomatoes", "watermelon balls") alike. Portions still
  # pointing at a purged unit are reconciled (unit nulled, description kept) and
  # any recipe that used it is deleted via its full cascade
  # (Measurements.purge_junk_measurement_unit/1). Must run after the insert
  # transaction commits, so its own transaction can't roll the import back.
  defp cleanup_junk_units(foods) do
    foods
    |> Enum.flat_map(fn food -> food["foodPortions"] || [] end)
    |> Enum.flat_map(&candidate_unit_names/1)
    |> Enum.uniq()
    |> Enum.reject(&Food.real_unit_name?/1)
    |> Enum.each(&Food.purge_junk_measurement_unit/1)
  end

  defp candidate_unit_names(portion) do
    modifier_name =
      case normalize_unit_name(portion["modifier"]) do
        nil -> nil
        modifier -> elem(get_measurement_unit_foul_name(modifier), 0)
      end

    [measure_unit_name(portion), modifier_name]
    |> Enum.reject(&is_nil/1)
  end

  # --- Nutrients ------------------------------------------------------------

  defp get_or_create_nutrient(ingredient, food_nutrient) do
    nutrient_attrs = food_nutrient["nutrient"]

    case get_or_create_measurement_unit(nutrient_attrs["unitName"], ingredient) do
      nil ->
        Logger.info(
          "Skipping nutrient #{inspect(nutrient_attrs["name"])} for #{inspect(ingredient.name)} — no measurement unit"
        )

        :skip

      measurement_unit ->
        nutrient = fetch_or_create_nutrient(nutrient_attrs, measurement_unit)
        create_ingredient_nutrient(ingredient, nutrient, food_nutrient)
    end
  end

  defp fetch_or_create_nutrient(nutrient_attrs, measurement_unit) do
    attrs = %{
      reference_id: nutrient_attrs["id"],
      number: nutrient_attrs["number"],
      name: nutrient_attrs["name"],
      rank: nutrient_attrs["rank"],
      measurement_unit_id: measurement_unit.id
    }

    case Food.get_nutrient(attrs.name, attrs.measurement_unit_id) do
      nil ->
        {:ok, nutrient} = Food.create_nutrient(attrs)
        nutrient

      nutrient ->
        nutrient
    end
  end

  defp create_ingredient_nutrient(ingredient, nutrient, food_nutrient) do
    Food.create_ingredient_nutrient(%{
      ingredient_id: ingredient.id,
      nutrient_id: nutrient.id,
      # FDC omits the amount for some nutrients; store a sentinel instead of nil.
      amount: food_nutrient["amount"] || -1.0,
      median: food_nutrient["median"],
      data_points: food_nutrient["dataPoints"],
      type_: food_nutrient["type"]
    })
  end

  # --- Measurement units ----------------------------------------------------

  # FDC portions/nutrients occasionally carry a blank or missing unit name (e.g. a
  # branded food portion with an empty "modifier"). A blank name can never satisfy
  # MeasurementUnit's required :name, so we return nil and callers skip the record
  # that references it. The parser never invents a placeholder unit.
  defp normalize_unit_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_unit_name(_), do: nil

  defp get_or_create_measurement_unit(measurement_unit_name, ingredient) do
    case normalize_unit_name(measurement_unit_name) do
      nil ->
        nil

      name ->
        # Resolve the canonical full name up front and look it up by *that* — the
        # same value we'd insert. Looking up by the raw modifier ("g") while
        # inserting the full name ("gram") let an existing "gram" row slip past the
        # lookup and then collide on the unique name index, aborting the batch's
        # transaction.
        {full_name, abbreviation} = get_measurement_unit_foul_name(name)
        result = Food.get_measurement_unit_by_name(full_name)

        Logger.info(
          "For #{inspect(ingredient.name)} Get/Create measurement unit with name #{full_name} and the search result replied #{inspect(result)}"
        )

        case result do
          [measurement_unit | _] -> measurement_unit
          [] -> create_measurement_unit(full_name, abbreviation)
        end
    end
  end

  defp create_measurement_unit(full_name, abbreviation) do
    # This insert runs inside the caller's batch transaction. A raised unique_constraint
    # violation would abort that whole transaction, so every subsequent query (including
    # the re-fetch below) would fail with 25P02. Insert idempotently instead: ON CONFLICT
    # DO NOTHING never raises, so a row that already exists — or a concurrent insert that
    # wins the race on the unique name index — leaves the transaction intact.
    {:ok, measurement_unit} =
      Food.create_measurement_unit(
        %{name: full_name, alternate_name: abbreviation},
        on_conflict: :nothing,
        conflict_target: :name
      )

    case measurement_unit do
      # On conflict nothing is inserted, so the returned struct has no generated id;
      # re-fetch the existing/winning row to get the real record.
      %{id: nil} ->
        case Food.get_measurement_unit_by_name(full_name) do
          [existing | _] -> existing
          [] -> raise "Could not get or create measurement unit #{inspect(full_name)}"
        end

      measurement_unit ->
        measurement_unit
    end
  end

  # Given an abbreviation or a full name, return the `{full_name, abbreviation}`
  # pair from the known-units table, or `{value, value}` when it isn't known.
  defp get_measurement_unit_foul_name(abbriviation) do
    result =
      Enum.filter(@measurement_unit_dict, fn {x, y} -> y == abbriviation or x == abbriviation end)

    case result do
      [{name, abbriviation}] -> {name, abbriviation}
      _ -> {abbriviation, abbriviation}
    end
  end

  # --- Batch entry points ---------------------------------------------------

  defp get_json(filename) do
    with {:ok, body} <- File.read(filename), {:ok, json} <- Poison.decode(body), do: {:ok, json}
  end

  def get_ingredients_from_food_data_central_json_file(file_path) do
    {:ok, json_body} = get_json(file_path)

    foods =
      Map.get(json_body, "SRLegacyFoods", []) ++
        Map.get(json_body, "SurveyFoods", []) ++
        Map.get(json_body, "FoundationFoods", []) ++
        Map.get(json_body, "BrandedFoods", [])

    Enum.each(foods, fn food -> create_ingredient(food) end)
    cleanup_junk_units(foods)
  end

  @doc """
  Parses a JSON array of FDC-format foods and inserts them (with portions,
  nutrients, units, and categories) inside a single transaction, so a failure
  mid-batch rolls everything back instead of leaving partial rows.

  Returns `{:ok, count}` or `{:error, reason}`.
  """
  def get_ingredients_from_json_body(json_body, nutrient_data_source \\ nil) do
    case Poison.decode(json_body) do
      {:ok, decoded} ->
        case normalize_foods(decoded) do
          {:ok, foods} ->
            result =
              Mehungry.Repo.transaction(fn ->
                Enum.each(foods, fn x -> create_ingredient(x, nutrient_data_source) end)
                length(foods)
              end)

            # Sweep the bogus units the reparsed portions used to reference, but
            # only after the transaction commits (delete rescues FK violations,
            # which would be useless inside an aborted transaction).
            with {:ok, _count} <- result, do: cleanup_junk_units(foods)

            result

          :error ->
            Logger.error(
              "[FoodData.Usda.FoodParser] Expected a JSON array of foods or an FDC dataset object, got: #{inspect(decoded, limit: 5)}"
            )

            {:error, :not_a_list}
        end

      {:error, reason} ->
        Logger.error("[FoodData.Usda.FoodParser] JSON decode failed: #{inspect(reason)}")
        {:error, {:invalid_json, reason}}
    end
  rescue
    error ->
      Logger.error(
        "[FoodData.Usda.FoodParser] Ingredient batch insert failed and was rolled back: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, error}
  end

  # FDC bulk downloads wrap foods in a dataset object (e.g.
  # %{"FoundationFoods" => [...]}) — that is the raw file shape uploaded to S3
  # for seeding. Accept either that wrapper (concatenating every known dataset
  # key, mirroring get_ingredients_from_food_data_central_json_file/1) or a bare
  # JSON array of food objects. Anything else is rejected as not-a-list.
  defp normalize_foods(body) when is_list(body), do: {:ok, body}

  defp normalize_foods(%{} = body) do
    foods =
      Enum.flat_map(
        ["SRLegacyFoods", "SurveyFoods", "FoundationFoods", "BrandedFoods"],
        fn key -> Map.get(body, key, []) end
      )

    if foods == [], do: :error, else: {:ok, foods}
  end

  defp normalize_foods(_), do: :error
end
