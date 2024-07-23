defmodule Mehungry.Accounts.UserCategoryRule do
  use Ecto.Schema
  import Ecto.Changeset
  alias Mehungry.Accounts.UserProfile

  schema "user_category_rules" do
    field :user_id, :id
    field(:delete, :boolean, virtual: true)

    belongs_to :user_profile, UserProfile
    belongs_to :category, Mehungry.Food.Category
    belongs_to :food_restriction_type, Mehungry.Food.FoodRestrictionType

    timestamps()
  end

  @doc false
  def changeset(user_category_rule, attrs) do
    changeset =
      user_category_rule
      |> cast(attrs, [
        :user_profile_id,
        :user_id,
        :food_restriction_type_id,
        :category_id,
        :delete
      ])
      |> validate_required([:category_id, :user_id, :food_restriction_type_id])

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
