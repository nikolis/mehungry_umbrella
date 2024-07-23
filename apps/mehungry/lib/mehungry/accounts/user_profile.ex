defmodule Mehungry.Accounts.UserProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_profiles" do
    field :alias, :string
    field :intro, :string
    field :onboarding_level, :integer

    belongs_to :user, Mehungry.Accounts.User
    has_many :user_category_rules, Mehungry.Accounts.UserCategoryRule
    has_many :user_ingredient_rules, Mehungry.Accounts.UserIngredientRule
    timestamps()
  end

  @doc false
  def changeset(user_profile, attrs) do
    user_profile
    |> cast(attrs, [:alias, :intro, :user_id, :onboarding_level])
    |> validate_required([:user_id])
    |> cast_assoc(:user_category_rules,
      with: &Mehungry.Accounts.UserCategoryRule.changeset/2,
      on_replace: :delete
    )
    |> cast_assoc(:user_ingredient_rules)
  end
end
