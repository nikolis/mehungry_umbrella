defmodule Mehungry.Repo.Migrations.CreateParserVocabulary do
  use Ecto.Migration

  def change do
    create table(:canonical_foods) do
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:canonical_foods, [:name])

    create table(:canonical_food_aliases) do
      add :canonical_food_id, references(:canonical_foods, on_delete: :delete_all), null: false
      add :alias, :string, null: false

      timestamps()
    end

    create unique_index(:canonical_food_aliases, [:alias])
    create index(:canonical_food_aliases, [:canonical_food_id])

    create table(:parser_processing_methods) do
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:parser_processing_methods, [:name])

    create table(:parser_processing_aliases) do
      add :processing_method_id, references(:parser_processing_methods, on_delete: :delete_all),
        null: false

      add :alias, :string, null: false
      add :implied_canonical_food_id, references(:canonical_foods, on_delete: :nilify_all)
      add :head_template, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:parser_processing_aliases, [:alias])
    create index(:parser_processing_aliases, [:processing_method_id])

    create table(:parser_harvest_stages) do
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:parser_harvest_stages, [:name])

    create table(:parser_harvest_stage_aliases) do
      add :harvest_stage_id, references(:parser_harvest_stages, on_delete: :delete_all),
        null: false

      add :alias, :string, null: false

      timestamps()
    end

    create unique_index(:parser_harvest_stage_aliases, [:alias])
    create index(:parser_harvest_stage_aliases, [:harvest_stage_id])

    create table(:parser_packaging_aliases) do
      add :alias, :string, null: false
      add :packaging, :string, null: false

      timestamps()
    end

    create unique_index(:parser_packaging_aliases, [:alias])

    create table(:parser_descriptor_aliases) do
      add :alias, :string, null: false
      add :kind, :string, null: false

      timestamps()
    end

    create unique_index(:parser_descriptor_aliases, [:alias])
    create index(:parser_descriptor_aliases, [:kind])
  end
end
