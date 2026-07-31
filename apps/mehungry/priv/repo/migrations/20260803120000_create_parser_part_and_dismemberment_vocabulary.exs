defmodule Mehungry.Repo.Migrations.CreateParserPartAndDismembermentVocabulary do
  use Ecto.Migration

  def change do
    create table(:parser_parts) do
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:parser_parts, [:name])

    create table(:parser_part_aliases) do
      add :part_id, references(:parser_parts, on_delete: :delete_all), null: false
      add :alias, :string, null: false

      timestamps()
    end

    create unique_index(:parser_part_aliases, [:alias])
    create index(:parser_part_aliases, [:part_id])

    create table(:parser_dismemberments) do
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:parser_dismemberments, [:name])

    create table(:parser_dismemberment_aliases) do
      add :dismemberment_id, references(:parser_dismemberments, on_delete: :delete_all),
        null: false

      add :alias, :string, null: false

      timestamps()
    end

    create unique_index(:parser_dismemberment_aliases, [:alias])
    create index(:parser_dismemberment_aliases, [:dismemberment_id])
  end
end
