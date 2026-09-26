defmodule Mehungry.Repo.Migrations.CreateConditionStates do
  use Ecto.Migration

  # A per-condition disease **state / phase** registry (e.g. Ulcerative Colitis →
  # "Active Flare", "Remission"). Dietary advice is often state-dependent — the same
  # food can be encouraged in remission and harmful during a flare — so a
  # recommendation may be tagged with a `condition_state`. A recommendation with no
  # state (`condition_state_id = nil`) is general / all-phase.
  #
  # Most conditions have zero states and behave exactly as before; only the
  # phase-sensitive ones (IBD, diverticular disease, gout, pancreatitis, CKD…) get
  # seeded states.
  def up do
    create table(:condition_states) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :is_default, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :description, :text

      timestamps()
    end

    # One state per (condition, slug); a condition's states are ordered by `position`.
    create unique_index(:condition_states, [:condition_id, :slug])
    create index(:condition_states, [:condition_id])
  end

  def down do
    drop table(:condition_states)
  end
end
