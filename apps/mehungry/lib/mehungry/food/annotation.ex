defmodule Mehungry.Food.Annotation do
  @moduledoc "Designed to represent the annotations on a recipe I.E greek cusine, fitness, vegetarion etc"

  use Ecto.Schema
  import Ecto.Changeset

  schema "annotations" do
    field :at, :integer
    field :body, :string

    belongs_to :user, Mehungry.Accounts.User
    belongs_to :recipe, Mehungry.Food.Recipe

    timestamps()
  end

  @doc false
  def changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:body, :at])
    |> validate_required([:body, :at])
  end
end
