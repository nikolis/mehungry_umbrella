defmodule Mehungry.Repo.Migrations.AddParentConditionIdToConditions do
  use Ecto.Migration

  # Self-referential parent link so a condition can be a subtype of a broader one
  # (e.g. Ulcerative Colitis / Crohn's Disease → Inflammatory Bowel Disease). Used
  # to surface the parent's (general) dietary suggestions under the child, clearly
  # labelled. Nilify on parent delete so the child survives.
  def change do
    alter table(:conditions) do
      add :parent_condition_id, references(:conditions, on_delete: :nilify_all)
    end

    create index(:conditions, [:parent_condition_id])
  end
end
