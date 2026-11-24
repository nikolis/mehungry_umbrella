defmodule Mehungry.Repo.Migrations.CreateSeasonalityTables do
  use Ecto.Migration

  # Tables of the self-contained seasonality app (apps/mehungry_seasonality). They live
  # in this shared migration folder because the project has one database and one
  # migration timeline; the `seasonality_` prefix is the boundary. Nothing outside that
  # app reads or writes them. See docs/implementation/seasonality.md.
  def change do
    species = fn ->
      references(:foundemental_food_species, on_delete: :delete_all)
    end

    # species ↔ external product crosswalk (agri-food portal product / Comext HS code)
    create table(:seasonality_mappings) do
      add :foundemental_species_id, species.(), null: false
      add :source, :string, null: false
      add :external_code, :string, null: false
      add :label, :string

      timestamps()
    end

    create unique_index(
             :seasonality_mappings,
             [:foundemental_species_id, :source, :external_code],
             name: :seasonality_mappings_species_source_code_index
           )

    # raw local-production signal (weeks with a producer price quote)
    create table(:seasonality_local_observations) do
      add :foundemental_species_id, species.(), null: false
      add :country, :string, size: 2, null: false
      add :month, :integer, null: false
      add :weeks_quoted, :integer, null: false, default: 0
      add :weeks_possible, :integer, null: false, default: 0
      add :years, {:array, :integer}, null: false, default: []
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(
             :seasonality_local_observations,
             [:foundemental_species_id, :country, :month],
             name: :seasonality_local_obs_species_country_month_index
           )

    # raw import signal (average monthly tonnes + top origins)
    create table(:seasonality_import_observations) do
      add :foundemental_species_id, species.(), null: false
      add :country, :string, size: 2, null: false
      add :month, :integer, null: false
      add :tonnes_avg, :float, null: false, default: 0.0
      add :origins, {:array, :map}, null: false, default: []
      add :years, {:array, :integer}, null: false, default: []
      add :retrieved_at, :utc_datetime

      timestamps()
    end

    create unique_index(
             :seasonality_import_observations,
             [:foundemental_species_id, :country, :month],
             name: :seasonality_import_obs_species_country_month_index
           )

    # the result: derived + admin-curated status per month
    create table(:seasonality_month_statuses) do
      add :foundemental_species_id, species.(), null: false
      add :country, :string, size: 2, null: false
      add :month, :integer, null: false
      add :local, :string, null: false, default: "unknown"
      add :imported, :string, null: false, default: "unknown"
      add :top_origins, {:array, :map}, null: false, default: []
      add :local_curated, :boolean, null: false, default: false
      add :imported_curated, :boolean, null: false, default: false
      add :note, :text

      timestamps()
    end

    create unique_index(
             :seasonality_month_statuses,
             [:foundemental_species_id, :country, :month],
             name: :seasonality_month_statuses_species_country_month_index
           )

    create index(:seasonality_month_statuses, [:country])

    # per-species run tracking for the admin fetch fan-out
    create table(:seasonality_runs) do
      add :batch_id, :string, null: false
      add :foundemental_species_id, species.(), null: false
      add :country, :string, size: 2, null: false
      add :status, :string, null: false, default: "pending"
      add :local_count, :integer, null: false, default: 0
      add :import_count, :integer, null: false, default: 0
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:seasonality_runs, [:batch_id])
    create index(:seasonality_runs, [:country, :status])

    create unique_index(:seasonality_runs, [:batch_id, :foundemental_species_id, :country],
             name: :seasonality_runs_batch_species_country_index
           )
  end
end
