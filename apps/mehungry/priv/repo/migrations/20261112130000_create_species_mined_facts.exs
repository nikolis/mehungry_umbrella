defmodule Mehungry.Repo.Migrations.CreateSpeciesMinedFacts do
  use Ecto.Migration

  # One row per biomedical fact mined from the external biomed-fact-miner
  # (`POST /mine`) for a `FoundementalFoodSpecies`. Columns flatten the API's
  # FactVerdict wrapper (label/certainty/reason/conflicting_pmid/assessment) and
  # its inner MinedFact (text + PMID citation + license + verbatim quote span).
  #
  # The per-species row set is fully REPLACED on each mine (wipe-then-insert), so
  # the natural key is `(species, fact_id)`. `quote` is only stored when the
  # source license is `commercial_ok` — non-commercial/unknown quotes are left
  # nil (the API redacts them under `?view=public`; we never persist the
  # "[quote withheld …]" placeholder).
  def change do
    create table(:species_mined_facts) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      # FactVerdict
      add :label, :string, null: false
      add :certainty, :string
      add :reason, :text
      add :conflicting_pmid, :string
      add :assessment, :map

      # MinedFact
      add :fact_id, :string, null: false
      add :text, :text, null: false
      add :claim_type, :string
      add :evidence_id, :string
      add :pmid, :string
      add :quote, :text
      add :char_span, {:array, :integer}
      add :study_design, :string
      add :source, :string
      add :pmcid, :string
      add :doi, :string
      add :pub_status, :map
      add :structured_effect, :map
      add :license, :string
      add :license_raw, :string
      add :scope_kind, :string

      timestamps()
    end

    create index(:species_mined_facts, [:foundemental_species_id])
    create index(:species_mined_facts, [:foundemental_species_id, :label])
    create index(:species_mined_facts, [:pmid])

    create unique_index(:species_mined_facts, [:foundemental_species_id, :fact_id],
             name: :species_mined_facts_natural_key_index
           )
  end
end
