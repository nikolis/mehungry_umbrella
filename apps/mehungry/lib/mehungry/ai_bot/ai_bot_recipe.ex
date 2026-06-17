defmodule Mehungry.AiBot.AiBotRecipe do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_meal_types ~w(breakfast morning_snack lunch afternoon_snack dinner)
  @valid_statuses ~w(pending_review approved rejected published)

  schema "ai_bot_recipes" do
    field :meal_type, :string
    field :scheduled_date, :date
    field :status, :string, default: "pending_review"

    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :bot_config, Mehungry.AiBot.AiBotConfig
    has_many :social_media_post_logs, Mehungry.AiBot.SocialMediaPostLog

    timestamps()
  end

  def changeset(bot_recipe, attrs) do
    bot_recipe
    |> cast(attrs, [:recipe_id, :bot_config_id, :meal_type, :scheduled_date, :status])
    |> validate_required([:recipe_id, :bot_config_id, :meal_type, :scheduled_date])
    |> validate_inclusion(:meal_type, @valid_meal_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:bot_config_id, :meal_type, :scheduled_date])
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:bot_config_id)
  end

  def valid_statuses, do: @valid_statuses
  def valid_meal_types, do: @valid_meal_types
end
