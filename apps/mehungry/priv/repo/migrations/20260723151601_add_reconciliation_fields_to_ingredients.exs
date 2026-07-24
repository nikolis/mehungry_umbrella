defmodule Mehungry.Repo.Migrations.AddReconciliationFieldsToIngredients do
  use Ecto.Migration

  # All four columns are metadata-only changes in PostgreSQL 14:
  #   * the three nullable columns add no default, so no table rewrite;
  #   * `version` uses a *constant* default, which PG11+ records as a catalog
  #     default without rewriting existing rows.
  # The momentary ACCESS EXCLUSIVE lock is only held for the catalog update,
  # so this is safe to run online with zero downtime.
  def change do
    alter table(:ingredients) do
      # Monotonic per-row reconciliation counter. Each reconciliation pass that
      # touches a row bumps this, so passes can select rows they haven't handled
      # yet and stay idempotent if interrupted and re-run.
      add :version, :integer, default: 0, null: false

      # The real USDA dataset discriminator (Foundation / SR Legacy / Branded /
      # Survey (FNDDS)). Currently overloaded onto `food_class`; backfilled from
      # it by IngredientReconciliationWorker.
      add :data_type, :string

      # Keys back to the USDA source records for future reconciliation passes.
      add :fdc_id, :bigint
      add :ndb_number, :bigint
    end
  end
end
