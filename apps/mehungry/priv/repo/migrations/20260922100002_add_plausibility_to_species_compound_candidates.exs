defmodule Mehungry.Repo.Migrations.AddPlausibilityToSpeciesCompoundCandidates do
  use Ecto.Migration

  # The LLM plausibility gate's verdict, cached per candidate so re-derivation
  # reuses it (nil = not yet judged). `verdict` is `plausible | implausible |
  # uncertain`; `reason` is the model's one-line justification, surfaced in the
  # admin review queue.
  def change do
    alter table(:species_compound_candidates) do
      add :plausibility_verdict, :string
      add :plausibility_reason, :text
      add :plausibility_checked_at, :naive_datetime
    end

    create index(:species_compound_candidates, [:plausibility_verdict])
  end
end
