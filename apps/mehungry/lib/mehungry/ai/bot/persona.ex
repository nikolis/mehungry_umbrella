defmodule Mehungry.AI.Bot.Persona do
  @moduledoc """
  A reusable authoring voice for AI-bot recipes — e.g. "Village Grandma",
  "Local Tavern", "Dietologist". The `voice_prompt` is injected into the
  RecipeAgent's system prompt and its persona-voiced polish step so the
  generated recipe reads as if authored by this character rather than a
  generic AI food writer.

  A persona is bound to a place/story/ingredients/condition by an
  `AI.Bot.RecipeSetup`; the same persona can back many setups.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_bot_personas" do
    field :name, :string
    field :archetype, :string
    field :description, :string
    field :voice_prompt, :string
    field :uses_hashtags, :boolean, default: false
    field :default_origin, :string
    field :active, :boolean, default: true

    has_many :recipe_setups, Mehungry.AI.Bot.RecipeSetup

    timestamps()
  end

  def changeset(persona, attrs) do
    persona
    |> cast(attrs, [
      :name,
      :archetype,
      :description,
      :voice_prompt,
      :uses_hashtags,
      :default_origin,
      :active
    ])
    |> validate_required([:name, :voice_prompt])
    |> unique_constraint(:name)
  end
end
