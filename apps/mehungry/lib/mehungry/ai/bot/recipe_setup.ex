defmodule Mehungry.AI.Bot.RecipeSetup do
  @moduledoc """
  A reusable, named creative bundle for AI-bot recipe generation: a persona
  (voice), an `origin` place, an optional `story`, an optional health
  `condition`, and a set of seed ingredients tagged with roles
  (primary/garnish/spice/avoid).

  A setup is decoupled from the calendar: the monthly `AiBotConfig` may
  reference one, and an ad-hoc `RecipeOrder` generates N recipes against one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_bot_recipe_setups" do
    field :name, :string
    field :cuisine, :string
    field :origin, :string
    field :story, :string
    field :diet_direction, :string
    field :active, :boolean, default: true

    belongs_to :persona, Mehungry.AI.Bot.Persona
    belongs_to :condition, Mehungry.Health.Condition

    has_many :seed_ingredients, Mehungry.AI.Bot.RecipeSetupIngredient,
      foreign_key: :recipe_setup_id

    timestamps()
  end

  def changeset(setup, attrs) do
    setup
    |> cast(attrs, [
      :name,
      :cuisine,
      :persona_id,
      :origin,
      :story,
      :condition_id,
      :diet_direction,
      :active
    ])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> foreign_key_constraint(:persona_id)
    |> foreign_key_constraint(:condition_id)
  end
end
