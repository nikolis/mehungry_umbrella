defmodule Mehungry.Food.PortionConversion do
  @moduledoc """
  Single source of truth for ingredient-portion unit conversion.

  An `IngredientPortion` records `gram_weight` grams for `amount` units of a
  measurement unit, so `grams_per_unit = gram_weight / amount` (see
  `Mehungry.Food.NutrientCalculation.calculate_gram_weight/5`). The unit itself
  is food-agnostic — it carries no density — so:

    * **Mass** units convert by an ingredient-independent constant
      (`1 kg = 1000 g` for every food), and a mass portion can be synthesized
      with no anchor.
    * **Volume** units convert by a fixed geometric ratio (`1 cup = 16 tbsp`),
      but grams-per-unit depends on the ingredient's density. Given **one**
      volume portion with a `gram_weight` you know that density (`grams_per_ml`),
      and every other volume portion follows.

  These constants and the density anchor were first written inline in
  `Mehungry.ReconcileRecipeIngredientPortions`; they live here now so that sweep
  and the `IngredientPortionGenerationWorker` share one definition. The buggy
  `BackfillAll{Mass,Volume}Units` scripts stored the *inverse* factor and must
  not be used.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{IngredientPortion, MeasurementUnit}

  # Correct grams-per-one-unit for mass units, keyed by canonical token.
  # Ingredient-independent, so a mass portion can be created without an anchor.
  @grams_per_unit %{
    "g" => 1.0,
    "mg" => 0.001,
    "kg" => 1000.0,
    "oz" => 28.3495,
    "lb" => 453.592
  }

  # Millilitres-per-one-unit for volume units, keyed by canonical token.
  # Grams-per-unit for a volume depends on density, so synthesis needs an
  # existing volume portion of the same ingredient as an anchor.
  @ml_per_unit %{
    "ml" => 1.0,
    "tsp" => 5.0,
    "tbsp" => 15.0,
    "cup" => 240.0,
    "liter" => 1000.0,
    "fl_oz" => 29.5735,
    "pint" => 473.0,
    "quart" => 946.0,
    "gallon" => 3785.0
  }

  # Maps the many surface spellings of a unit — the DB has both "teaspoon" (a
  # measurement-unit name) and "tsp" (a portion description) — onto one canonical
  # token so name-matching and volume anchoring treat them as equal. Keys are
  # already lower-cased; lookups downcase first, so matching is case-insensitive.
  @unit_aliases %{
    # mass
    "g" => "g",
    "gr" => "g",
    "gram" => "g",
    "grams" => "g",
    "grammar" => "g",
    "mg" => "mg",
    "milligram" => "mg",
    "milligrams" => "mg",
    "kg" => "kg",
    "kilogram" => "kg",
    "kilograms" => "kg",
    "oz" => "oz",
    "ounce" => "oz",
    "ounces" => "oz",
    "lb" => "lb",
    "lbs" => "lb",
    "pound" => "lb",
    "pounds" => "lb",
    # volume
    "ml" => "ml",
    "cc" => "ml",
    "milliliter" => "ml",
    "millilitre" => "ml",
    "milliliters" => "ml",
    "millilitres" => "ml",
    "tsp" => "tsp",
    "teaspoon" => "tsp",
    "teaspoons" => "tsp",
    "tbsp" => "tbsp",
    "tbs" => "tbsp",
    "tbl" => "tbsp",
    "tablespoon" => "tbsp",
    "tablespoons" => "tbsp",
    "cup" => "cup",
    "cups" => "cup",
    "l" => "liter",
    "liter" => "liter",
    "litre" => "liter",
    "liters" => "liter",
    "litres" => "liter",
    "fl oz" => "fl_oz",
    "fl. oz." => "fl_oz",
    "floz" => "fl_oz",
    "fluid ounce" => "fl_oz",
    "fluid ounces" => "fl_oz",
    "fluid_ounce" => "fl_oz",
    "pint" => "pint",
    "pints" => "pint",
    "pt" => "pint",
    "quart" => "quart",
    "quarts" => "quart",
    "qt" => "quart",
    "gallon" => "gallon",
    "gallons" => "gallon",
    "gal" => "gallon",
    # count
    "piece" => "piece",
    "pieces" => "piece"
  }

  # The metric + common-recipe units the portion-generation sweep materializes.
  # `g` is deliberately excluded — it is the implicit base every unit picker
  # already appends. Imperial and count units are out of scope.
  @target_mass ~w(kg)
  @target_volume ~w(ml liter tsp tbsp cup)

  @doc "Canonical token for a unit name/description (case-insensitive, alias-aware)."
  def canonical_unit(s) when is_binary(s) do
    n = s |> String.downcase() |> String.trim()
    Map.get(@unit_aliases, n, n)
  end

  def canonical_unit(_), do: nil

  @doc "Grams-per-one-unit for a mass unit, or `nil` if `name` is not a mass unit."
  def mass_grams_per_unit(name) when is_binary(name), do: Map.get(@grams_per_unit, canonical_unit(name))
  def mass_grams_per_unit(_), do: nil

  @doc "Millilitres-per-one-unit for a volume unit, or `nil` if not a volume unit."
  def volume_ml_per_unit(name) when is_binary(name), do: Map.get(@ml_per_unit, canonical_unit(name))
  def volume_ml_per_unit(_), do: nil

  @doc "The mass/volume canonical tokens the generation sweep creates portions for."
  def target_mass, do: @target_mass
  def target_volume, do: @target_volume

  @doc """
  All known surface spellings (lower-cased) that canonicalize to `token` — used
  to find an existing `MeasurementUnit` for a target token before minting one.
  """
  def alias_names_for(token) when is_binary(token) do
    for {surface, canon} <- @unit_aliases, canon == token, do: surface
  end

  @doc """
  The ingredient's density in grams-per-millilitre, derived from its
  lowest-`id` volume portion (the deterministic anchor) — a unit-bearing portion
  whose unit is a volume unit, **or** a description-only portion whose
  description names a volume unit (e.g. a "cup" portion with no measurement
  unit). Returns `{:ok, grams_per_ml}` or `:none` when the ingredient has no
  volume portion to anchor on.
  """
  @spec grams_per_ml(integer()) :: {:ok, float()} | :none
  def grams_per_ml(ingredient_id) do
    from(ip in IngredientPortion,
      left_join: mu in MeasurementUnit,
      on: mu.id == ip.measurement_unit_id,
      where: ip.ingredient_id == ^ingredient_id and not is_nil(ip.gram_weight) and ip.gram_weight > 0.0,
      order_by: [asc: ip.id],
      select: %{gw: ip.gram_weight, amount: ip.amount, unit_name: mu.name, desc: ip.description}
    )
    |> Repo.all()
    |> Enum.find_value(:none, &density_from_portion/1)
  end

  # grams-per-millilitre for one portion, or nil if it names no volume unit.
  defp density_from_portion(p) do
    if ml = portion_volume_ml(p) do
      amount = if is_number(p.amount) and p.amount > 0, do: p.amount, else: 1.0
      {:ok, p.gw / amount / ml}
    end
  end

  defp portion_volume_ml(%{unit_name: unit_name}) when is_binary(unit_name),
    do: volume_ml_per_unit(unit_name)

  defp portion_volume_ml(%{desc: desc}) when is_binary(desc), do: volume_ml_per_unit(desc)
  defp portion_volume_ml(_), do: nil
end
