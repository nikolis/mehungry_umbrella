defmodule Mehungry.BackfillAllMassUnits do
  @moduledoc """
  Backfills missing mass-based IngredientPortions for all ingredients.

  ## 🧠 Domain Context

  - `IngredientPortion.gram_weight` = grams per unit
  - This script ensures all mass units are available for each ingredient

  ## 🎯 Goal

  If an ingredient supports ANY mass unit (g, kg, oz, lb, mg),
  it should support ALL of them.

  ## 🔁 Conversion Strategy

  We normalize everything through **grams (g)**.

  Example:

      1 oz = 28.3495 g
      1 lb = 453.592 g
      1 kg = 1000 g
      1 mg = 0.001 g

  ### Steps:

  1. Convert source → grams
  2. Convert grams → target unit

  ---

  ## 📌 Example

      Input:
          oz → 28.3495g

      Normalize:
          grams_per_g = 28.3495 / 28.3495 = 1g

      Generate:
          g  → 1g
          kg → 1000g
          lb → 453.592g
          mg → 0.001g

  ---

  ## ✅ Behavior

  - Processes ALL IngredientPortions
  - Only affects mass units
  - Creates missing units per ingredient
  - Idempotent

  ---

  ## ▶️ Usage

      mix run priv/repo/seeds.exs

  or:

      Mehungry.Repo.Scripts.BackfillAllMassUnits.run()
  """

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.{IngredientPortion, MeasurementUnit, Ingredient}

  @to_grams %{
    "g" => 1.0,
    "grammar" => 1.0,
    "kg" => 1000.0,
    "mg" => 0.001,
    "oz" => 28.3495,
    "lb" => 453.592
  }

  @from_grams %{
    "g" => 1.0,
    "grammar" => 1.0,
    "kg" => 1.0 / 1000.0,
    "mg" => 1000.0,
    "oz" => 1.0 / 28.3495,
    "lb" => 1.0 / 453.592
  }

  @batch_size 500

  def run do
    units = load_units!(Map.keys(@to_grams))

    IO.puts("Starting FULL mass unit backfill...\n")

    Ingredient
    |> Repo.all()
    |> Enum.chunk_every(@batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      IO.puts("Processing batch #{index + 1}...")

      Enum.each(batch, fn ingredient ->
        process_ingredient(ingredient, units)
      end)
    end)

    IO.puts("\n✅ Backfill completed.")
  end

  # ------------------------
  # CORE LOGIC
  # ------------------------

  defp process_ingredient(ingredient, units) do
    # unit_name = get_unit_name(portion.measurement_unit_id)

    # if Map.has_key?(@to_grams, unit_name) do
    # grams = to_grams(portion.gram_weight, unit_name)

    Enum.each(@from_grams, fn {target_name, factor} ->
      target_unit = Map.fetch!(units, target_name)

      unless exists?(ingredient.id, target_unit.id) do
        new_gw = factor
        create_portion(ingredient, target_unit.id, new_gw)
        log(ingredient, target_name, target_name, new_gw)
      end
    end)
  end

  # ------------------------
  # CONVERSIONS
  # ------------------------

  defp to_grams(gram_weight, unit_name) do
    factor = Map.fetch!(@to_grams, unit_name)
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

  defp load_units!(names) do
    MeasurementUnit
    |> where([mu], mu.name in ^names)
    |> Repo.all()
    |> Map.new(&{&1.name, &1})
  end

  defp get_unit_name(id) do
    Repo.get!(MeasurementUnit, id).name
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

  defp create_portion(ingredient, unit_id, gram_weight) do
    attrs = %{
      ingredient_id: ingredient.id,
      measurement_unit_id: unit_id,
      amount: nil,
      value: nil,
      gram_weight: gram_weight
      # reference_id: portion.reference_id,
      # min_year_acquired: portion.min_year_acquired,
      # sequence_number: portion.sequence_number
    }

    %IngredientPortion{}
    |> IngredientPortion.changeset(attrs)
    |> Repo.insert!()
  end

  defp log(ingredient, from, to, new_weight) do
    IO.puts(
      "✔ Ingredient #{ingredient.id}: #{from} → #{to} (#{Float.round(new_weight, 4)}g → #{Float.round(new_weight, 4)}g)"
    )
  end
end
