defmodule Mehungry.History.IngredientUserMeal do
  @moduledoc false

  use Ecto.Schema

  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.IngredientPortion
  alias Mehungry.History.UserMeal

  import Ecto.Changeset

  schema "history_ingredient_user_meals" do
    belongs_to :ingredient, Ingredient
    belongs_to :user_meal, UserMeal
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    # The portion this logged ingredient resolves to. Nil for gram-family rows
    # (which have no IngredientPortion); set to the chosen portion otherwise.
    # Mirrors `RecipeIngredient` so the nutrition engine scales identically.
    belongs_to :ingredient_portion, IngredientPortion

    field :quantity, :float

    # Form-only unit picker value, identical in meaning to
    # `RecipeIngredient.unit_selection`:
    #   positive → a `measurement_unit_id` (unit-bearing portion or grams)
    #   negative → `-ingredient_portion_id` (a description-only portion with no
    #              measurement unit, e.g. "1 medium banana")
    # Parsed by `changeset/2` into the real FKs.
    field :unit_selection, :integer, virtual: true
    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(ingredient_user_meal, attrs) do
    attrs = normalize_unit_selection(attrs)

    changeset =
      ingredient_user_meal
      |> cast(attrs, [
        :ingredient_id,
        :user_meal_id,
        :measurement_unit_id,
        :ingredient_portion_id,
        :unit_selection,
        :quantity,
        :delete
      ])
      |> apply_unit_selection()
      |> validate_required([:quantity, :ingredient_id])
      |> validate_unit_or_portion()

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end

  @doc """
  The value the unit dropdown should show as selected for a persisted row: the
  `-ingredient_portion_id` encoding for description-only portions (no unit),
  otherwise the `measurement_unit_id`. Mirrors `RecipeIngredient`.
  """
  def unit_selection_value(%__MODULE__{measurement_unit_id: nil, ingredient_portion_id: pid})
      when not is_nil(pid),
      do: -pid

  def unit_selection_value(%__MODULE__{measurement_unit_id: mu_id}), do: mu_id

  # Drops a blank `unit_selection` param so casting an empty string to :integer
  # does not add a spurious changeset error when nothing is chosen yet.
  defp normalize_unit_selection(attrs) when is_map(attrs) do
    cond do
      Map.get(attrs, "unit_selection") in ["", nil] and Map.has_key?(attrs, "unit_selection") ->
        Map.delete(attrs, "unit_selection")

      Map.get(attrs, :unit_selection) in ["", nil] and Map.has_key?(attrs, :unit_selection) ->
        Map.delete(attrs, :unit_selection)

      true ->
        attrs
    end
  end

  defp normalize_unit_selection(attrs), do: attrs

  # Splits the form's `unit_selection` into the real FKs. Positive → a real
  # measurement unit; negative → a description-only portion with no unit. No-op
  # when the caller sent `measurement_unit_id`/`ingredient_portion_id` directly.
  defp apply_unit_selection(changeset) do
    case get_change(changeset, :unit_selection) do
      nil ->
        changeset

      sel when sel >= 0 ->
        changeset
        |> put_change(:measurement_unit_id, sel)
        |> put_change(:ingredient_portion_id, nil)

      sel ->
        changeset
        |> put_change(:ingredient_portion_id, -sel)
        |> put_change(:measurement_unit_id, nil)
    end
  end

  # A row must resolve to either a measurement unit (grams / unit-bearing
  # portion) or a description-only portion.
  defp validate_unit_or_portion(changeset) do
    if is_nil(get_field(changeset, :measurement_unit_id)) and
         is_nil(get_field(changeset, :ingredient_portion_id)) do
      add_error(changeset, :measurement_unit_id, "can't be blank")
    else
      changeset
    end
  end
end
