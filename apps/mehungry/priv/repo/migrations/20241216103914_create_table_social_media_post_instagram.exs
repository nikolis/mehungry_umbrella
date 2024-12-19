defmodule Mehungry.Repo.Migrations.CreateTableSocialMediaPostInstagram do
  use Ecto.Migration

  def change do
    create table(:social_media_posts_instagram) do
      add :resource_id, :integer
      add :type_, :string
      add :user_id, references(:users, on_delete: :delete_all)
    end

    create index(:social_media_posts_instagram, [:user_id])
  end
end
