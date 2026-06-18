defmodule Mehungry.AiBot.DayConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_bot_day_configs" do
    field :date, :date
    field :focus_hint, :string

    belongs_to :bot_config, Mehungry.AiBot.AiBotConfig

    timestamps()
  end

  def changeset(day_config, attrs) do
    day_config
    |> cast(attrs, [:bot_config_id, :date, :focus_hint])
    |> validate_required([:bot_config_id, :date, :focus_hint])
    |> unique_constraint([:bot_config_id, :date])
    |> foreign_key_constraint(:bot_config_id)
  end
end
