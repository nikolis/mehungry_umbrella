defmodule Mehungry.Accounts.UserProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_profiles" do
    field :alias, :string
    field :intro, :string
    field :onboarding_level, :integer
    field :language_preference, :string, default: "en"
    field :daily_calorie_target, :integer
    field :diet, :string, default: "omnivore"
    field :lactose_intolerant, :boolean, default: false

    belongs_to :user, Mehungry.Accounts.User

    has_many :user_category_rules, Mehungry.Accounts.UserCategoryRule, on_replace: :delete
    has_many :user_ingredient_rules, Mehungry.Accounts.UserIngredientRule
    has_many :user_condition_opt_ins, Mehungry.Accounts.UserConditionOptIn

    timestamps()
  end

  @doc false
  def changeset(user_profile, attrs) do
    user_profile
    |> cast(attrs, [
      :alias,
      :intro,
      :user_id,
      :onboarding_level,
      :language_preference,
      :daily_calorie_target,
      :diet,
      :lactose_intolerant
    ])
    |> validate_required([:user_id])
    |> validate_number(:daily_calorie_target, greater_than: 0, less_than: 20_000)
    |> validate_inclusion(:diet, ~w(omnivore vegetarian vegan pescatarian))
    |> cast_assoc(:user_category_rules,
      with: &Mehungry.Accounts.UserCategoryRule.changeset/2
    )
    |> cast_assoc(:user_ingredient_rules)
  end
end
