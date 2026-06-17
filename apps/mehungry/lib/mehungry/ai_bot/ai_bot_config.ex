defmodule Mehungry.AiBot.AiBotConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @meal_types ~w(breakfast morning_snack lunch afternoon_snack dinner)

  schema "ai_bot_configs" do
    field :theme, :string
    field :month, :integer
    field :year, :integer
    field :active, :boolean, default: true
    field :pinterest_default_board_id, :string
    field :facebook_page_id, :string
    # JSONB map: %{"breakfast" => %{"en" => "07:00:00", "el" => "08:00:00"}, ...}
    field :publish_times, :map, default: %{}
    # Per-language targets: %{"en" => "page_id", "el" => "page_id"}
    field :facebook_page_ids, :map, default: %{}
    # Per-language Pinterest boards: %{"en" => "board_id", "el" => "board_id"}
    field :pinterest_board_ids, :map, default: %{}

    belongs_to :bot_user, Mehungry.Accounts.User
    has_many :ai_bot_recipes, Mehungry.AiBot.AiBotRecipe, foreign_key: :bot_config_id

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:theme, :month, :year, :bot_user_id, :active, :pinterest_default_board_id, :facebook_page_id, :publish_times, :facebook_page_ids, :pinterest_board_ids])
    |> validate_required([:theme, :month, :year, :bot_user_id])
    |> validate_inclusion(:month, 1..12)
    |> validate_number(:year, greater_than: 2020)
    |> unique_constraint([:month, :year])
    |> foreign_key_constraint(:bot_user_id)
  end

  def meal_types, do: @meal_types
end
