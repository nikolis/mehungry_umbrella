defmodule Mehungry.Accounts.UserConditionOptIn do
  @moduledoc """
  A user opting into health-condition badges. When a profile opts into a
  `Mehungry.Health.Condition`, recipes carrying a compound flagged for that
  condition surface a badge. Mirrors `UserCategoryRule` (a cross-context
  reference into another context's schema is the established pattern here).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.UserProfile

  schema "user_condition_opt_ins" do
    belongs_to :user_profile, UserProfile
    belongs_to :condition, Mehungry.Health.Condition

    timestamps()
  end

  @doc false
  def changeset(user_condition_opt_in, attrs) do
    user_condition_opt_in
    |> cast(attrs, [:user_profile_id, :condition_id])
    |> validate_required([:user_profile_id, :condition_id])
    |> unique_constraint([:user_profile_id, :condition_id],
      name: :user_condition_opt_ins_profile_condition_index
    )
  end
end
