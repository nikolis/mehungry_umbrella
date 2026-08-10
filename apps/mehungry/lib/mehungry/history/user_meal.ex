defmodule Mehungry.History.UserMeal do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.History.ConsumeRecipeUserMeal
  alias Mehungry.History.RecipeUserMeal
  alias Mehungry.History.IngredientUserMeal
  alias Mehungry.History.MealType

  schema "history_user_meals" do
    field :start_dt, :naive_datetime
    field :end_dt, :naive_datetime
    field :title, :string
    field :meal_type, :string
    field :user_id, :id

    has_many :recipe_user_meals, RecipeUserMeal, on_replace: :delete, on_delete: :nothing
    has_many :ingredient_user_meals, IngredientUserMeal, on_replace: :delete, on_delete: :nothing

    has_many :consume_recipe_user_meals, ConsumeRecipeUserMeal,
      on_replace: :delete,
      on_delete: :nothing

    timestamps()
  end

  @doc false
  def changeset(user_meal, attrs) do
    user_meal
    |> cast(normalize_meal_type(attrs), [:title, :meal_type, :start_dt, :end_dt, :user_id])
    |> cast_assoc(:recipe_user_meals, with: &RecipeUserMeal.changeset/2, required: false)
    |> cast_assoc(:ingredient_user_meals, with: &IngredientUserMeal.changeset/2, required: false)
    |> cast_assoc(:consume_recipe_user_meals,
      with: &ConsumeRecipeUserMeal.changeset/2,
      required: false
    )
    |> maybe_put_default_title()
    |> validate_meal_type()
    |> validate_required([:title, :user_id])
  end

  # The form's "Unsorted" button and any blank submission arrive as
  # "unsorted"/"" — collapse both to nil (the unsorted bucket) so string- and
  # atom-keyed attrs behave the same before casting.
  defp normalize_meal_type(%{"meal_type" => mt} = attrs) when mt in ["unsorted", ""],
    do: Map.put(attrs, "meal_type", nil)

  defp normalize_meal_type(%{meal_type: mt} = attrs) when mt in ["unsorted", ""],
    do: Map.put(attrs, :meal_type, nil)

  defp normalize_meal_type(attrs), do: attrs

  # The form's title input is now derived rather than typed, so backfill a
  # sensible title from the chosen meal_type (or a generic fallback) before the
  # required check, keeping `validate_required(:title)` satisfied.
  defp maybe_put_default_title(changeset) do
    case get_field(changeset, :title) do
      title when is_binary(title) and title != "" ->
        changeset

      _blank ->
        title =
          case get_field(changeset, :meal_type) do
            nil -> "Meal"
            meal_type -> MealType.label(meal_type)
          end

        put_change(changeset, :title, title)
    end
  end

  # `nil` meal_type is the valid "unsorted" bucket; only validate concrete values.
  defp validate_meal_type(changeset) do
    case get_field(changeset, :meal_type) do
      nil -> changeset
      _value -> validate_inclusion(changeset, :meal_type, MealType.values())
    end
  end
end
