defmodule Mehungry.Repo.Migrations.CreateCompoundTranslations do
  use Ecto.Migration

  def change do
    create table(:compound_translations) do
      add :name, :string
      add :description, :text

      add :compound_id, references(:compounds, on_delete: :delete_all), null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all),
          null: false

      add :status, :string, default: "verified", null: false
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:compound_translations, [:compound_id, :language_name])
    create index(:compound_translations, [:language_name, :status])
  end
end
