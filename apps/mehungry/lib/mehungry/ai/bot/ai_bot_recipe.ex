defmodule Mehungry.AI.Bot.AiBotRecipe do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_meal_types ~w(breakfast morning_snack lunch afternoon_snack dinner)
  @valid_statuses ~w(pending_review approved rejected published)

  schema "ai_bot_recipes" do
    field :meal_type, :string
    field :scheduled_date, :date
    field :status, :string, default: "pending_review"

    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :bot_config, Mehungry.AI.Bot.AiBotConfig
    belongs_to :recipe_order, Mehungry.AI.Bot.RecipeOrder
    has_many :social_media_post_logs, Mehungry.AI.Bot.SocialMediaPostLog

    timestamps()
  end

  def changeset(bot_recipe, attrs) do
    bot_recipe
    |> cast(attrs, [
      :recipe_id,
      :bot_config_id,
      :recipe_order_id,
      :meal_type,
      :scheduled_date,
      :status
    ])
    |> validate_required([:recipe_id, :meal_type, :scheduled_date])
    |> validate_config_or_order()
    |> validate_inclusion(:meal_type, @valid_meal_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint([:bot_config_id, :meal_type, :scheduled_date])
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:bot_config_id)
    |> foreign_key_constraint(:recipe_order_id)
  end

  # A bot recipe belongs to either a calendar config or an ad-hoc order.
  defp validate_config_or_order(changeset) do
    if get_field(changeset, :bot_config_id) || get_field(changeset, :recipe_order_id) do
      changeset
    else
      add_error(changeset, :bot_config_id, "either bot_config_id or recipe_order_id is required")
    end
  end

  def valid_statuses, do: @valid_statuses
  def valid_meal_types, do: @valid_meal_types
end
