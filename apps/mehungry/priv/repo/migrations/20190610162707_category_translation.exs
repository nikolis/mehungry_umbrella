defmodule MehungryServer.Repo.Migrations.CategoryTranslation do
  use Ecto.Migration

  def change do
    create table(:category_translations) do
      add :name, :string

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all)

      add :category_id, references(:categories, on_delete: :delete_all)

      timestamps()
    end

    create index(:category_translations, [:name])
  end
end
