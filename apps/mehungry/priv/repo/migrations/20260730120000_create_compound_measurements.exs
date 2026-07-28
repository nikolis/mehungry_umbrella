defmodule Mehungry.Repo.Migrations.CreateCompoundMeasurements do
  use Ecto.Migration

  # Quantitative scientific-measurement layer for the compound registry.
  #
  # Each row is one immutable observation of a compound in an ingredient as
  # reported by a research paper — e.g. "Spinach, Oxalate, Raw: 750 mg/100g".
  # Measurements are append-only: historical values are never updated, a new
  # study reporting a different value inserts a new row, and aggregation across
  # rows is a separate read-only concern. Like the rest of the compound layer,
  # this table is keyed by ingredient_id/compound_id and is never read or
  # written by the USDA ingestion/reconciliation path.
  def up do
    create table(:compound_measurements) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      # Optional: manual entries may predate cataloging the paper as a study.
      # nilify (not delete) so an immutable value survives its study being pruned.
      add :study_id, references(:scientific_studies, on_delete: :nilify_all)

      add :value, :float, null: false
      add :unit, :string, null: false
      # Sample state the paper measured: Raw, Boiled, Steamed, Dried, …
      add :preparation_method, :string
      # Lab technique the paper used: HPLC, spectrophotometry, enzymatic assay, …
      add :analytical_method, :string
      add :sample_size, :integer
      add :confidence, :float
      # How this data point entered our system: manual | automated | pdf.
      add :extraction_method, :string, null: false

      timestamps()
    end

    # Idempotent re-extraction of a study's data must not duplicate rows: one
    # measurement per (study, ingredient, compound, preparation, analytical
    # method). A re-run inserts nothing rather than overwriting the value, which
    # is what keeps measurements immutable. (Rows with a NULL study_id — manual
    # entries with no cataloged paper — are treated as distinct by Postgres and
    # are not deduped.)
    create unique_index(
             :compound_measurements,
             [:study_id, :ingredient_id, :compound_id, :preparation_method, :analytical_method],
             name: :compound_measurements_natural_key_index
           )

    create index(:compound_measurements, [:compound_id])
    create index(:compound_measurements, [:study_id])
    create index(:compound_measurements, [:ingredient_id, :compound_id])
  end

  def down do
    drop table(:compound_measurements)
  end
end
