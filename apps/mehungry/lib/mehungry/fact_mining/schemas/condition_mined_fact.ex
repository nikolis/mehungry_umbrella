defmodule Mehungry.FactMining.ConditionMinedFact do
  @moduledoc """
  A single biomedical fact mined from the external **biomed-fact-miner**
  (`POST /mine`) for a `Mehungry.Health.Condition` — the condition-scope
  counterpart of `Mehungry.FactMining.SpeciesMinedFact`.

  For each condition the miner is asked a **relational** question (`"give me all
  the food related facts about {name}"`) and every returned `FactSheet.fact` is
  stored as one row — a distilled, PMID-cited claim carrying the API's honest
  verification `label` (verified/contradicted/unverified_*), its `certainty`, and
  the source `license`.

  One row per `(condition, fact_id)`; the whole per-condition set is replaced on
  each mine (wipe-then-insert), so there is no incremental upsert. `quote` (the
  verbatim source span) is stored **only** when `license == "commercial_ok"` — we
  never persist the redaction placeholder the API returns for non-commercial
  sources under `?view=public`. The `license` is the "right to present" gate the
  nutritionist surface reads: `commercial_ok` → shown with its quote; everything
  else → a "free claim" (distilled text + source link only). See
  `docs/implementation/fact_mining.md`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition

  @labels ~w(verified contradicted unverified_quality unverified_fulltext
             unverified_insufficient unverified_verification)
  @certainties ~w(high moderate low very_low)

  schema "condition_mined_facts" do
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

    # Lay presentation hint (FactVerdict.lay) — orthogonal to `label`: `lay_tier`
    # lead/show/hide ("hide" = off-subject), `lay_clarity` [0,1] readability, and
    # `lay_flags` the demotion reasons. Mirrors SpeciesMinedFact (shared ingest).
    field :lay_tier, :string
    field :lay_clarity, :float
    field :lay_flags, {:array, :string}

    belongs_to :condition, Condition

    timestamps()
  end

  @castable ~w(condition_id label certainty reason conflicting_pmid assessment
               fact_id text claim_type evidence_id pmid quote char_span study_design source
               pmcid doi pub_status structured_effect license license_raw scope_kind
               lay_tier lay_clarity lay_flags)a

  def changeset(fact, attrs) do
    fact
    |> cast(attrs, @castable)
    |> validate_required([:condition_id, :label, :fact_id, :text])
    |> validate_inclusion(:label, @labels)
    |> validate_inclusion(:certainty, @certainties)
    |> foreign_key_constraint(:condition_id)
    |> unique_constraint([:condition_id, :fact_id],
      name: :condition_mined_facts_natural_key_index
    )
  end

  @doc "The valid verification `label` values."
  def labels, do: @labels

  @doc "The valid `certainty` values."
  def certainties, do: @certainties
end
