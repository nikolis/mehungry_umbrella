defmodule Mehungry.Survey.Demographic do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "demographics" do
    field :capacity, :string
    field :year_of_birth, :integer

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(demographic, attrs) do
    demographic
    |> cast(attrs, [:capacity, :year_of_birth, :user_id])
    |> validate_required([:capacity, :year_of_birth, :user_id])
    |> validate_inclusion(
      :capacity,
      ["Foodie", "Cook", "Dietologist", "Prefer not to say"]
    )
    |> validate_inclusion(:year_of_birth, 1900..2022)
    |> unique_constraint(:user_id)
  end
end
