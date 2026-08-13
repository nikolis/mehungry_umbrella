defmodule Mehungry.AI.Bot.RecipeSetupIngredient do
  @moduledoc """
  A seed ingredient attached to a `RecipeSetup` with a role:

  - `primary`  — build the recipe around it
  - `garnish`  — finishing touch, optional
  - `spice`    — seasoning / aromatic
  - `avoid`    — hard exclude (enforced by the generation guard)

  `avoid` roles can be auto-populated from the setup's condition via
  `Mehungry.AI.Bot.populate_setup_ingredients_from_condition/1`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(primary garnish spice avoid)

  schema "ai_bot_recipe_setup_ingredients" do
    field :role, :string

    belongs_to :recipe_setup, Mehungry.AI.Bot.RecipeSetup
    belongs_to :ingredient, Mehungry.Food.Ingredient

    timestamps()
  end

  def changeset(setup_ingredient, attrs) do
    setup_ingredient
    |> cast(attrs, [:recipe_setup_id, :ingredient_id, :role])
    |> validate_required([:recipe_setup_id, :ingredient_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:recipe_setup_id, :ingredient_id, :role])
    |> foreign_key_constraint(:recipe_setup_id)
    |> foreign_key_constraint(:ingredient_id)
  end

  def roles, do: @roles
end
