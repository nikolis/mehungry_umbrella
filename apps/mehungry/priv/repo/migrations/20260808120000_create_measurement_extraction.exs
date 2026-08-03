defmodule Mehungry.Repo.Migrations.CreateMeasurementExtraction do
  use Ecto.Migration

  @moduledoc """
  Data surface for the measurement-extraction feature. Fetch + extraction run in the
  non-deployed `mehungry_local_ai` service; the server keeps only these tables:

    * `study_full_texts` — fetched PMC open-access full text per study.
    * `pmc_fetch_attempts` — per-study fetch ledger (dedupe + termination).
    * `compound_measurement_candidates` — review-gated extracted measurements.
  """

  def change do
    create table(:study_full_texts) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :pmcid, :string
      add :source, :string
      add :body, :text
      add :retrieved_at, :utc_datetime
      timestamps()
    end

    create unique_index(:study_full_texts, [:study_id])

    create table(:pmc_fetch_attempts) do
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :pmcid, :string
      add :outcome, :string, null: false
      add :last_attempted_at, :utc_datetime
      timestamps()
    end

    create unique_index(:pmc_fetch_attempts, [:study_id])

    create table(:compound_measurement_candidates) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      add :study_id, references(:scientific_studies, on_delete: :delete_all), null: false
      add :value, :float, null: false
      add :unit, :string, null: false
      add :preparation_method, :string
      add :analytical_method, :string
      add :sample_size, :integer
      add :score, :float
      add :raw_span, :text
      add :extraction_method, :string, null: false, default: "automated"
      add :status, :string, null: false, default: "pending"

      add :accepted_measurement_id,
          references(:compound_measurements, on_delete: :nilify_all)

      timestamps()
    end

    create index(:compound_measurement_candidates, [:status])
    create index(:compound_measurement_candidates, [:foundemental_species_id])

    create unique_index(
             :compound_measurement_candidates,
             [:study_id, :foundemental_species_id, :compound_id, :value, :unit],
             name: :compound_measurement_candidates_natural_key_index
           )
  end
end
