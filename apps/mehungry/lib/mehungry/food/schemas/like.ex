defmodule Mehungry.Food.Like do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "likes" do
    field :at, :integer

    belongs_to :user, Mehungry.Accounts.User
    belongs_to :recipe, Mehungry.Food.Recipe

    timestamps()
  end

  @doc false
  def changeset(like, attrs) do
    like
    |> cast(attrs, [:at])
    |> validate_required([:at])
  end
end
