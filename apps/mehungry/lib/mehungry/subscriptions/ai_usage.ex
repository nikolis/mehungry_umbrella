defmodule Mehungry.Subscriptions.AiUsage do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_usage" do
    field :feature, :string
    field :used_at, :naive_datetime

    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [:user_id, :feature, :used_at])
    |> validate_required([:user_id, :feature, :used_at])
    |> validate_inclusion(:feature, ["recipe_generation", "meal_plan"])
    |> foreign_key_constraint(:user_id)
  end
end
