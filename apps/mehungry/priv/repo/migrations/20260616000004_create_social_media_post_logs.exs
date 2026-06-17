defmodule Mehungry.Repo.Migrations.CreateSocialMediaPostLogs do
  use Ecto.Migration

  def change do
    create table(:social_media_post_logs) do
      add :ai_bot_recipe_id, references(:ai_bot_recipes, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :status, :string, null: false
      add :language_name, :string
      add :error, :text
      add :posted_at, :utc_datetime

      timestamps()
    end

    create index(:social_media_post_logs, [:ai_bot_recipe_id])
    create index(:social_media_post_logs, [:platform, :status])
  end
end
