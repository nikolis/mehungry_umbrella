defmodule Mehungry.Food.RecipeIngredient do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Mehungry.Food.IngredientPortion

  schema "recipe_ingredients" do
    field :quantity, :float
    field :ingredient_allias, :string

    field :delete, :boolean, virtual: true
    field :temp_id, :string, virtual: true
    # Form-only unit picker value. Encodes the chosen option as an integer:
    #   positive  → a `measurement_unit_id` (unit-bearing portion or grams)
    #   negative  → `-ingredient_portion_id` (a description-only USDA portion
    #               that has no measurement unit, e.g. "1 medium banana")
    # Parsed by `changeset/2` into the real FKs. Non-form callers keep sending
    # `measurement_unit_id`/`ingredient_portion_id` directly and ignore this.
    field :unit_selection, :integer, virtual: true

    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit
    # The portion this row resolves to. Nil for gram-family units (which have no
    # IngredientPortion); set to a description-only portion when the row has no
    # measurement unit. See `changeset/2` and `Recipes` nutrition read paths.
    belongs_to :ingredient_portion, Mehungry.Food.IngredientPortion
    belongs_to :ingredient, Mehungry.Food.Ingredient

    timestamps()
  end

  @doc false
  def changeset(recipe_ingredient, attrs) do
    attrs = normalize_unit_selection(attrs)

    recipe_ingredient
    # So its persisted
    # So its persisted
    |> Map.put(:temp_id, recipe_ingredient.temp_id || attrs["temp_id"])
    |> cast(attrs, [
      :quantity,
      :ingredient_allias,
      :measurement_unit_id,
      :ingredient_portion_id,
      :unit_selection,
      :ingredient_id,
      :recipe_id,
      :delete,
      :temp_id
    ])
    |> apply_unit_selection()
    |> maybe_mark_for_deletion()
    |> validate_required([:ingredient_id, :quantity])
    |> validate_unit_or_portion()
    |> maybe_resolve_ingredient_portion()
    |> foreign_key_constraint(:name)
    |> foreign_key_constraint(:recipe_ingredients_name_fkey)
    |> foreign_key_constraint(:recipe_ingredients_name)
    |> foreign_key_constraint(:recipe_ingredients)
    |> foreign_key_constraint(:ingredient_id)
    |> foreign_key_constraint(:ingredient_portion_id)
  end

  # The value the unit dropdown should show as selected for a persisted row:
  # the `-ingredient_portion_id` encoding for description-only portions,
  # otherwise the `measurement_unit_id` (unit-bearing portion or grams).
  def unit_selection_value(%__MODULE__{measurement_unit_id: nil, ingredient_portion_id: pid})
      when not is_nil(pid),
      do: -pid

  def unit_selection_value(%__MODULE__{measurement_unit_id: mu_id}), do: mu_id

  @doc """
  Human-readable unit label for a recipe ingredient, tolerant of a nil unit.

  Prefers the measurement unit's name; falls back to the linked portion's
  display name (its free-text description) for description-only portions; and
  finally to "g" so a bare gram row never renders blank.

  Accepts a `%RecipeIngredient{}` or any map with `:measurement_unit` /
  `:ingredient_portion` keys (the social publishers pass plain maps).
  """
  def unit_label(recipe_ingredient) do
    unit = Map.get(recipe_ingredient, :measurement_unit)
    portion = Map.get(recipe_ingredient, :ingredient_portion)

    cond do
      is_map(unit) and is_binary(Map.get(unit, :name)) ->
        unit.name

      match?(%IngredientPortion{}, portion) ->
        IngredientPortion.display_name(portion) || "g"

      true ->
        "g"
    end
  end

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
  # measurement unit (portion re-derived in `maybe_resolve_ingredient_portion`);
  # negative → a description-only portion with no unit. No-op when the caller
  # sent `measurement_unit_id`/`ingredient_portion_id` directly (non-form paths).
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
  # portion) or a description-only portion. Mirrors the old
  # `validate_required([:measurement_unit_id])` while allowing unit-less portions.
  defp validate_unit_or_portion(changeset) do
    if is_nil(get_field(changeset, :measurement_unit_id)) and
         is_nil(get_field(changeset, :ingredient_portion_id)) do
      add_error(changeset, :measurement_unit_id, "can't be blank")
    else
      changeset
    end
  end

  # Keeps `ingredient_portion_id` in sync with the selected
  # `(ingredient_id, measurement_unit_id)` on every persisted save. Runs via
  # `prepare_changes/2` so it only touches the DB at insert/update time (not
  # while the recipe form is being re-rendered) and resolves per-row, avoiding
  # any parent-level rewrite of the `recipe_ingredients` association. Grams and
  # any unit without a matching portion resolve to `nil` — the nutrition engine
  # treats a nil portion as "quantity is already grams". Skipped when the unit is
  # nil (a description-only portion already set its own `ingredient_portion_id`).
  defp maybe_resolve_ingredient_portion(changeset) do
    prepare_changes(changeset, fn cs ->
      ingredient_id = get_field(cs, :ingredient_id)
      unit_id = get_field(cs, :measurement_unit_id)

      if is_nil(ingredient_id) or is_nil(unit_id) do
        cs
      else
        portion_id =
          cs.repo.one(
            from p in IngredientPortion,
              where: p.ingredient_id == ^ingredient_id and p.measurement_unit_id == ^unit_id,
              order_by: [asc: p.id],
              limit: 1,
              select: p.id
          )

        put_change(cs, :ingredient_portion_id, portion_id)
      end
    end)
  end

  defp maybe_mark_for_deletion(%{data: %{id: nil}} = changeset) do
    changeset
  end

  defp maybe_mark_for_deletion(changeset) do
    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
