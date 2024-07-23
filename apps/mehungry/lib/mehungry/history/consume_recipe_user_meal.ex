defmodule Mehungry.History.ConsumeRecipeUserMeal do
  @moduledoc false

  alias Mehungry.History.RecipeUserMeal
  alias Mehungry.History

  use Ecto.Schema
  import Ecto.Changeset

  schema "history_consume_recipe_user_meals" do
    field :start_dt, :naive_datetime
    field :end_dt, :naive_datetime
    field :consume_portions, :integer

    field :delete, :boolean, virtual: true

    belongs_to :recipe_user_meal, RecipeUserMeal
    belongs_to :user_meal, UserMeal
  end

  @doc false
  def changeset(consume_recipe_user_meal, attrs) do
    changeset =
      consume_recipe_user_meal
      |> cast(attrs, [:recipe_user_meal_id, :consume_portions, :delete, :user_meal_id])
      |> validate_required([:consume_portions, :recipe_user_meal_id])
      |> validate_recipe_user_meal(:recipe_user_meal_id, attrs["consume_portions"])

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end

  def validate_recipe_user_meal(changeset, field, portions) when is_atom(field) do
    portions =
      case portions do
        nil ->
          0

        other ->
          other
      end

    if(changeset.valid?) do
      validate_change(changeset, field, fn field, value ->
        portions_left = History.get_available_portions_for_user_meal(value)

        portions =
          if(is_integer(portions)) do
            portions
          else
            {portions, _} = Integer.parse(portions)
            portions
          end

        case portions_left >= portions do
          true ->
            []

          false ->
            [{:consume_portions, "only " <> to_string(portions_left) <> " portions left"}]
        end
      end)
    else
      changeset
    end
  end
end
