defmodule Mehungry.AI.Bot.DayConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_bot_day_configs" do
    field :date, :date
    field :focus_hint, :string

    belongs_to :bot_config, Mehungry.AI.Bot.AiBotConfig
    belongs_to :recipe_setup, Mehungry.AI.Bot.RecipeSetup

    timestamps()
  end

  def changeset(day_config, attrs) do
    day_config
    |> cast(attrs, [:bot_config_id, :date, :focus_hint, :recipe_setup_id])
    |> validate_required([:bot_config_id, :date, :focus_hint])
    |> unique_constraint([:bot_config_id, :date])
    |> foreign_key_constraint(:bot_config_id)
    |> foreign_key_constraint(:recipe_setup_id)
  end
end
