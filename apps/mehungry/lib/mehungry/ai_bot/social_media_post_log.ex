defmodule Mehungry.AiBot.SocialMediaPostLog do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_platforms ~w(instagram facebook pinterest)
  @valid_statuses ~w(ok error skipped)

  schema "social_media_post_logs" do
    field :platform, :string
    field :status, :string
    field :language_name, :string
    field :error, :string
    field :posted_at, :utc_datetime

    belongs_to :ai_bot_recipe, Mehungry.AiBot.AiBotRecipe

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:ai_bot_recipe_id, :platform, :status, :language_name, :error, :posted_at])
    |> validate_required([:ai_bot_recipe_id, :platform, :status])
    |> validate_inclusion(:platform, @valid_platforms)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:ai_bot_recipe_id)
  end
end
