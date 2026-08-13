defmodule Mehungry.AI.Bot.RecipeOrder do
  @moduledoc """
  An ad-hoc request to generate `quantity` recipes for a `RecipeSetup`,
  outside the monthly calendar. The `RecipeOrderWorker` fulfils it, landing
  the generated recipes in the review queue as `pending_review` (no publish
  scheduling). A nil `meal_type` cycles across all meal types.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(pending generating completed failed)
  @valid_meal_types ~w(breakfast morning_snack lunch afternoon_snack dinner)

  schema "ai_bot_recipe_orders" do
    field :quantity, :integer
    field :meal_type, :string
    field :language_name, :string, default: "En"
    field :status, :string, default: "pending"
    field :completed_count, :integer, default: 0

    belongs_to :recipe_setup, Mehungry.AI.Bot.RecipeSetup
    belongs_to :bot_user, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :recipe_setup_id,
      :bot_user_id,
      :quantity,
      :meal_type,
      :language_name,
      :status,
      :completed_count
    ])
    |> validate_required([:recipe_setup_id, :bot_user_id, :quantity])
    |> validate_number(:quantity, greater_than: 0, less_than_or_equal_to: 50)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_meal_type()
    |> foreign_key_constraint(:recipe_setup_id)
    |> foreign_key_constraint(:bot_user_id)
  end

  defp validate_meal_type(changeset) do
    case get_field(changeset, :meal_type) do
      nil -> changeset
      "" -> put_change(changeset, :meal_type, nil)
      _ -> validate_inclusion(changeset, :meal_type, @valid_meal_types)
    end
  end

  def valid_statuses, do: @valid_statuses
  def valid_meal_types, do: @valid_meal_types
end
