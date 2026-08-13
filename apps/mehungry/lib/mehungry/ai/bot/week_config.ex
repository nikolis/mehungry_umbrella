defmodule Mehungry.AI.Bot.WeekConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_bot_week_configs" do
    field :week_number, :integer
    field :theme, :string

    belongs_to :bot_config, Mehungry.AI.Bot.AiBotConfig
    belongs_to :recipe_setup, Mehungry.AI.Bot.RecipeSetup

    timestamps()
  end

  def changeset(week_config, attrs) do
    week_config
    |> cast(attrs, [:bot_config_id, :week_number, :theme, :recipe_setup_id])
    |> validate_required([:bot_config_id, :week_number, :theme])
    |> validate_inclusion(:week_number, 1..6)
    |> unique_constraint([:bot_config_id, :week_number])
    |> foreign_key_constraint(:bot_config_id)
    |> foreign_key_constraint(:recipe_setup_id)
  end
end
