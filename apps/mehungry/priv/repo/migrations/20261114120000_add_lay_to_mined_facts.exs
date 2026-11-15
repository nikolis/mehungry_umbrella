defmodule Mehungry.Repo.Migrations.AddLayToMinedFacts do
  use Ecto.Migration

  # The biomed-fact-miner now returns a `lay` block per fact (`FactVerdict.lay`) —
  # a presentation hint orthogonal to the verification `label`:
  #   tier:    "lead" | "show" | "hide"   ("hide" = NOT about the query subject)
  #   clarity: float [0,1]                (deterministic readability score)
  #   flags:   ["off_subject:background", "undefined_acronym:GSE", ...]
  #
  # The rule is "relevance decides visibility, clarity only decides prominence":
  # `hide` facts are off-subject comparators/background, `lead`/`show` are on-subject
  # sorted by clarity. The species detail page uses tier+clarity to pick the curated,
  # SEO-visible top set and to push off-subject facts into search-only. Flattened
  # typed columns (not a jsonb map) so the top-N read can ORDER BY them directly.
  #
  # Added to BOTH mined-fact tables because the shared ingest
  # (`FactMining.row_from_verdict/5`) writes either. Nullable — existing rows (mined
  # before the miner exposed `lay`) stay NULL until the next wipe-insert re-mine.
  def change do
    for table <- [:species_mined_facts, :condition_mined_facts] do
      alter table(table) do
        add :lay_tier, :string
        add :lay_clarity, :float
        add :lay_flags, {:array, :string}
      end
    end

    # Supports the curated top-N read: filter (species, verified) then order by tier.
    create index(:species_mined_facts, [:foundemental_species_id, :label, :lay_tier])
  end
end
