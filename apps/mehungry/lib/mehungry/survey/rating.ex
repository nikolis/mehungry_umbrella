defmodule Mehungry.Survey.Rating do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Food.Recipe

  schema "ratings" do
    field :stars, :integer

    belongs_to :user, User
    belongs_to :recipe, Product

    timestamps()
  end

  @doc false
  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [:stars, :user_id, :recipe_id])
    |> validate_required([:stars, :user_id, :recipe_id])
    |> validate_inclusion(:stars, 1..5)
    |> unique_constraint(:recipe_id, name: :index_ratings_on_user_recipe)
  end
end
