defmodule Mehungry.Repo.Migrations.AddSeedProvenanceToMealBlueprints do
  use Ecto.Migration

  def change do
    alter table(:meal_blueprints) do
      # Provenance for blueprints instantiated from a DietPatterns template, so
      # DietPatterns.sync_for_user/1 can re-seed safely:
      #   * seeded_pattern_key — the DietPatterns key (e.g. "mediterranean"); nil
      #     for hand-made blueprints. The stable join back to the template.
      #   * seed_signature — content hash captured AT SEED TIME, so a later sync
      #     can tell "user-edited" (current content ≠ signature → skip) from
      #     "unedited" (equal → safe to overwrite to the latest template). nil
      #     means "do not auto-refresh" (legacy rows adopted by name carry a key
      #     but no signature, so their content is never overwritten).
      add :seeded_pattern_key, :string
      add :seed_signature, :string
    end
  end
end
