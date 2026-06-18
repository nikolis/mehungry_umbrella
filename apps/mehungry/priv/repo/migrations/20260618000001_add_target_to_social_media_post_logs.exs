defmodule Mehungry.Repo.Migrations.AddTargetToSocialMediaPostLogs do
  use Ecto.Migration

  def change do
    alter table(:social_media_post_logs) do
      add :target_id, :string
      add :target_name, :string
    end
  end
end
