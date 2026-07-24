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
    MeasurementUnitTranslation
  }

  alias Mehungry.Languages.Language

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

  def create_measurement_unit(attrs) do
    %MeasurementUnit{}
    |> MeasurementUnit.changeset(attrs)
    |> Repo.insert()
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

  def list_measurement_units() do
    Repo.all(MeasurementUnit)
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
