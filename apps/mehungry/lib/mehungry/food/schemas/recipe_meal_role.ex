defmodule Mehungry.Food.RecipeMealRole do
  @moduledoc """
  One meal role (`Mehungry.Food.MealRoles`) held by a recipe. A recipe has as
  many rows as it has roles (unique per `(recipe_id, role)`).

    * `source` — `"ai"` (written by `RecipeMealRoleClassifier`) or `"manual"`
      (added by an admin on `/professional/recipe-meal-roles`).
    * `confidence` — the classifier's 0..1 confidence; `nil` for manual rows.
    * `reviewed` — a human confirmed it (or the classifier was confident enough
      to auto-confirm). A recipe with any reviewed row is never re-written by
      the classifier.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Food.{MealRoles, Recipe}

  @sources ~w(ai manual)

  schema "recipe_meal_roles" do
    field :role, :string
    field :source, :string
    field :confidence, :float
    field :reviewed, :boolean, default: false
    field :reviewed_at, :utc_datetime

    belongs_to :recipe, Recipe
    belongs_to :reviewed_by, User

    timestamps()
  end

  def sources, do: @sources

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :recipe_id,
      :role,
      :source,
      :confidence,
      :reviewed,
      :reviewed_by_id,
      :reviewed_at
    ])
    |> validate_required([:recipe_id, :role, :source])
    |> validate_inclusion(:role, MealRoles.all())
    |> validate_inclusion(:source, @sources)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint([:recipe_id, :role])
  end
end
