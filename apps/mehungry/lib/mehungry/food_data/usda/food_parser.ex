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
    category = get_or_create_food_category(category_description(attrs))

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

  defp get_or_create_food_category(nil), do: nil

  defp get_or_create_food_category(category_name) do
    case Food.get_category_by_name(category_name) do
      nil ->
        {:ok, category} = Food.create_category(%{name: category_name})
        category

      category ->
        category
    end
  end

  # --- Portions -------------------------------------------------------------

  defp create_ingredient_portions(food_portions, ingredient) do
    food_portions
    |> Enum.map(fn portion ->
      {portion, get_or_create_measurement_unit(portion["modifier"], ingredient)}
    end)
    # A portion with no unit can't be stored; skip it rather than invent a unit.
    |> Enum.reject(fn {_portion, measurement_unit} -> is_nil(measurement_unit) end)
    |> Enum.each(fn {portion, measurement_unit} ->
      Food.create_ingredient_portion(%{
        amount: portion["amount"],
        value: portion["value"],
        gram_weight: portion["gramWeight"],
        reference_id: portion["id"],
        min_year_acquired: portion["minYearAcquired"],
        sequence_number: portion["sequenceNumber"],
        ingredient_id: ingredient.id,
        measurement_unit_id: measurement_unit.id
      })
    end)
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
        result = Food.get_measurement_unit_by_name(name)

        Logger.info(
          "For #{inspect(ingredient.name)} Get/Create measurement unit with name #{name} and the search result replied #{inspect(result)}"
        )

        case result do
          [measurement_unit | _] -> measurement_unit
          [] -> create_measurement_unit(name)
        end
    end
  end

  defp create_measurement_unit(name) do
    {full_name, abbreviation} = get_measurement_unit_foul_name(name)

    case Food.create_measurement_unit(%{name: full_name, alternate_name: abbreviation}) do
      {:ok, measurement_unit} ->
        measurement_unit

      # A concurrent insert can win the unique_constraint(:name) race; re-fetch
      # rather than turning it into a MatchError that rolls back the batch.
      {:error, _changeset} ->
        case Food.get_measurement_unit_by_name(full_name) do
          [measurement_unit | _] -> measurement_unit
          [] -> raise "Could not get or create measurement unit #{inspect(full_name)}"
        end
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
            Mehungry.Repo.transaction(fn ->
              Enum.each(foods, fn x -> create_ingredient(x, nutrient_data_source) end)
              length(foods)
            end)

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
