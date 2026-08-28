defmodule Mehungry.Repo.Migrations.CreateProfessionalArticleParagraphs do
  use Ecto.Migration

  def change do
    create table(:professional_article_paragraphs) do
      add :article_id, references(:professional_articles, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :heading, :string
      add :body, :text
      add :image_url, :string
      add :image_caption, :string

      timestamps()
    end

    create index(:professional_article_paragraphs, [:article_id])
  end
end
