defmodule Mehungry.FactMining.SpeciesMinedFact do
  @moduledoc """
  A single biomedical fact mined from the external **biomed-fact-miner**
  (`POST /mine`) for a `FoundementalFoodSpecies` — a distilled, PMID-cited claim
  (e.g. "Acerola is a rich source of vitamin C") carrying the API's honest
  verification `label` (verified/contradicted/unverified_*), its `certainty`, and
  the source `license`.

  One row per `(species, fact_id)`; the whole per-species set is replaced on each
  mine (wipe-then-insert), so there is no incremental upsert. `quote` (the verbatim
  source span) is stored **only** when `license == "commercial_ok"` — we never
  persist the redaction placeholder the API returns for non-commercial sources
  under `?view=public`. See `docs/implementation/fact_mining.md`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.FoundementalFoodSpecies

  @labels ~w(verified contradicted unverified_quality unverified_fulltext
             unverified_insufficient unverified_verification)
  @certainties ~w(high moderate low very_low)

  schema "species_mined_facts" do
    # FactVerdict
    field :label, :string
    field :certainty, :string
    field :reason, :string
    field :conflicting_pmid, :string
    field :assessment, :map

    # MinedFact
    field :fact_id, :string
    field :text, :string
    field :claim_type, :string
    field :evidence_id, :string
    field :pmid, :string
    field :quote, :string
    field :char_span, {:array, :integer}
    field :study_design, :string
    field :source, :string
    field :pmcid, :string
    field :doi, :string
    field :pub_status, :map
    field :structured_effect, :map
    field :license, :string
    field :license_raw, :string
    field :scope_kind, :string

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id

    timestamps()
  end

  @castable ~w(foundemental_species_id label certainty reason conflicting_pmid assessment
               fact_id text claim_type evidence_id pmid quote char_span study_design source
               pmcid doi pub_status structured_effect license license_raw scope_kind)a

  def changeset(fact, attrs) do
    fact
    |> cast(attrs, @castable)
    |> validate_required([:foundemental_species_id, :label, :fact_id, :text])
    |> validate_inclusion(:label, @labels)
    |> validate_inclusion(:certainty, @certainties)
    |> foreign_key_constraint(:foundemental_species_id)
    |> unique_constraint([:foundemental_species_id, :fact_id],
      name: :species_mined_facts_natural_key_index
    )
  end

  @doc "The valid verification `label` values."
  def labels, do: @labels

  @doc "The valid `certainty` values."
  def certainties, do: @certainties
end
