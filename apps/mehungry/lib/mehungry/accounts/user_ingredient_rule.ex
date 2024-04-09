defmodule Mehungry.Accounts.UserIngredientRule do
  use Ecto.Schema
  import Ecto.Changeset
  alias Mehungry.Accounts.UserProfile

  schema "user_ingredient_rules" do
    field :user_id, :id
    field :ingredient_id, :id
    field :food_restriction_type_id, :id

    field(:delete, :boolean, virtual: true)

    belongs_to :user_profile, UserProfile
    timestamps()
  end

  @doc false
  def changeset(user_ingredient_rule, attrs) do
    changeset =
      user_ingredient_rule
      |> cast(attrs, [:user_profile_id, :user_id, :food_restriction_type_id, :delete])
      |> validate_required([:user_profile_id, :user_id, :food_restriction_type_id, :ingredient_id])

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
