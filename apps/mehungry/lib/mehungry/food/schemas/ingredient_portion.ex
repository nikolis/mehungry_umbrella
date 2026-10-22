defmodule Mehungry.Food.IngredientPortion do
  use Ecto.Schema

  @moduledoc """
  IngredientPortion represents the portions of ingredients and connects bassically ingredients with measurmenet Units
  """

  import Ecto.Changeset

  schema "ingredient_portions" do
    field :amount, :float
    field :value, :float
    field :gram_weight, :float
    field :reference_id, :integer
    field :min_year_acquired, :integer
    field :sequence_number, :integer
    # Human-readable portion label taken from USDA `portionDescription` when the
    # portion has no real measurement unit (measureUnit "undetermined"/id 9999).
    field :description, :string

    belongs_to :ingredient, Mehungry.Food.Ingredient

    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    has_many :translation, Mehungry.Food.IngredientPortionTranslation, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(measurement_unit, attrs) do
    measurement_unit
    |> cast(attrs, [
      :value,
      :min_year_acquired,
      :reference_id,
      :gram_weight,
      :amount,
      :description,
      :ingredient_id,
      :measurement_unit_id,
      :ingredient_id
    ])
    # A portion no longer requires a measurement_unit: USDA portions with an
    # "undetermined" measureUnit keep only their `description`. It must have at
    # least one of the two so it can still be displayed.
    |> validate_required([:gram_weight])
    |> validate_has_unit_or_description()
  end

  # Display label for a portion: prefer the free-text description (from USDA
  # `portionDescription`), fall back to the linked measurement unit's name.
  # Both are passed through `strip_amount/1` so the quantity never shows — the
  # label is a *unit*, the count lives in the row's own `quantity`/`amount`.
  def display_name(%__MODULE__{description: desc}) when is_binary(desc) and desc != "",
    do: strip_amount(desc)

  def display_name(%__MODULE__{measurement_unit: %{name: name}}) when is_binary(name),
    do: strip_amount(name)

  def display_name(_), do: nil

  @doc """
  Strips numeric quantity tokens from a portion label so only the unit/measure
  survives: `"1 cup" → "cup"`, `"1 φλιτζάνι" → "φλιτζάνι"`, `"2 1/2 cups" →
  "cups"`, `"1,5 φλιτζάνι" → "φλιτζάνι"`. Collapses the whitespace left behind
  and trims any leading/trailing separators. A purely-numeric label (nothing
  left after stripping) is returned unchanged so it never renders blank.

  The canonical place portion labels are shown — every surface routes its label
  through here via `display_name/1` or the localized option builders — so the
  quantity is hidden consistently across recipe details, recipe creation, the
  calendar, and the REST API.
  """
  def strip_amount(label) when is_binary(label) do
    stripped =
      label
      # Remove digit runs (incl. decimals/fractions like "1/2", "1,5", "1.5").
      |> String.replace(~r/\d+([.,\/]\d+)*/u, " ")
      # Collapse the whitespace the removal left behind.
      |> String.replace(~r/\s+/u, " ")
      # Trim surrounding whitespace and orphaned separators ("8-ounce" → "ounce").
      |> String.replace(~r/^[\s\-.,\/]+|[\s\-.,\/]+$/u, "")

    if stripped == "", do: label, else: stripped
  end

  def strip_amount(other), do: other

  # USDA portion labels that are technical artifacts rather than a serving a
  # person would recognize: "RACC" is the Reference Amount Customarily Consumed
  # (a regulatory figure), "Quantity not specified" is a bare placeholder. These
  # are hidden from any user- or AI-facing portion list. Matched case-insensitively
  # as whole labels; overridable via `config :mehungry, :excluded_portion_labels`.
  @default_excluded_labels ["RACC", "Quantity not specified"]

  def excluded_labels do
    Application.get_env(:mehungry, :excluded_portion_labels, @default_excluded_labels)
  end

  @doc """
  True when `label` is a real, human-meaningful portion label (not blank and not
  in the static exclusion list). Use to filter portions before showing them to a
  user or handing them to the recipe AI.
  """
  def meaningful_label?(label) when is_binary(label) do
    norm = label |> String.trim() |> String.downcase()
    norm != "" and norm not in Enum.map(excluded_labels(), &String.downcase/1)
  end

  def meaningful_label?(_), do: false

  defp validate_has_unit_or_description(changeset) do
    unit_id = get_field(changeset, :measurement_unit_id)
    description = get_field(changeset, :description)

    if is_nil(unit_id) and (is_nil(description) or description == "") do
      add_error(changeset, :description, "portion needs a measurement unit or a description")
    else
      changeset
    end
  end
end
