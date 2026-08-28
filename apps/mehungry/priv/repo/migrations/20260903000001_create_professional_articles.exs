defmodule Mehungry.Repo.Migrations.CreateProfessionalArticles do
  use Ecto.Migration

  def change do
    create table(:professional_articles) do
      add :professional_profile_id, references(:professional_profiles, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :slug, :string, null: false
      add :summary, :text
      add :cover_image_url, :string
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime

      timestamps()
    end

    create unique_index(:professional_articles, [:slug])
    create index(:professional_articles, [:professional_profile_id])
    create index(:professional_articles, [:status])
  end
end
