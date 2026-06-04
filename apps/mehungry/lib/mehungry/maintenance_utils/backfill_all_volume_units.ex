defmodule Mehungry.BackfillAllVolumeUnits do
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.{IngredientPortion, MeasurementUnit}

  @to_ml %{
    "ml" => 1.0,
    "teaspoon" => 5.0,
    "tsp" => 5.0,
    "tablespoon" => 15.0,
    "tbsp" => 15.0,
    "cup" => 240.0,
    "liter" => 1000.0,
    # NEW
    "fluid_ounce" => 29.5735,
    "pint" => 473.0,
    "quart" => 946.0,
    "gallon" => 3785.0
  }

  @from_ml %{
    "ml" => 1.0,
    "teaspoon" => 1.0 / 5.0,
    "tsp" => 1.0 / 5.0,
    "tablespoon" => 1.0 / 15.0,
    "tbsp" => 1.0 / 15.0,
    "cup" => 1.0 / 240.0,
    "liter" => 1.0 / 1000,
    # NEW
    "fluid_ounce" => 1.0 / 29.5735,
    "pint" => 1.0 / 473.0,
    "quart" => 1.0 / 946.0,
    "gallon" => 1.0 / 3785.0
  }

  @batch_size 500

  def run do
    units = load_units!(Map.keys(@to_ml))

    IO.puts("Starting FULL volume unit backfill...\n")

    IngredientPortion
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      IO.puts("Processing batch #{index + 1}...")

      Enum.each(batch, fn portion ->
        process_portion(portion, units)
      end)
    end)

    IO.puts("\n✅ Backfill completed.")
  end

  # ------------------------
  # CORE LOGIC
  # ------------------------
  # IngredientPortion , String List (representing units) 
  defp process_portion(portion, units) do
    unit_name = get_unit_name(portion.measurement_unit_id)

    # skip non-volume units
    if Map.has_key?(@to_ml, unit_name) do
      ml_grams = to_ml_grams(portion.gram_weight, unit_name)

      Enum.each(@from_ml, fn {target_name, factor} ->
        target_unit = Map.fetch!(units, target_name)

        if not exists?(portion.ingredient_id, target_unit.id) do
          new_gw = ml_grams * factor
          create_portion(portion, target_unit.id, new_gw)
          log(portion, unit_name, target_name, new_gw)
        end
      end)
    end
  end

  # ------------------------
  # CONVERSIONS
  # ------------------------

  defp to_ml_grams(gram_weight, unit_name) do
    # gram_weight = grams per unit
    # convert to grams per ml
    factor = Map.fetch!(@to_ml, unit_name)
    gram_weight / factor
  end

  # ------------------------
  # HELPERS
  # ------------------------

  defp load_units!(names) do
    names
    |> Enum.map(fn name ->
      case Repo.get_by(MeasurementUnit, name: name) do
        nil ->
          IO.puts("⚠️ Creating missing MeasurementUnit: #{name}")

          %MeasurementUnit{}
          |> MeasurementUnit.changeset(%{name: name})
          |> Repo.insert!()

        unit ->
          unit
      end
    end)
    |> Map.new(&{&1.name, &1})
  end

  defp get_unit_name(id) do
    Mehungry.Repo.get!(MeasurementUnit, id).name
  end

  defp exists?(ingredient_id, unit_id) do
    IngredientPortion
    |> where(
      [ip],
      ip.ingredient_id == ^ingredient_id and
        ip.measurement_unit_id == ^unit_id
    )
    |> Repo.exists?()
  end

  defp create_portion(portion, unit_id, gram_weight) do
    attrs = %{
      ingredient_id: portion.ingredient_id,
      measurement_unit_id: unit_id,
      amount: nil,
      value: nil,
      gram_weight: gram_weight,
      reference_id: portion.reference_id,
      min_year_acquired: portion.min_year_acquired,
      sequence_number: portion.sequence_number
    }

    %IngredientPortion{}
    |> IngredientPortion.changeset(attrs)
    |> Repo.insert!()
  end

  defp log(portion, from, to, new_weight) do
    IO.puts(
      "✔ Ingredient #{portion.ingredient_id}: #{from} → #{to} (#{Float.round(portion.gram_weight, 2)}g → #{Float.round(new_weight, 4)}g)"
    )
  end
end
