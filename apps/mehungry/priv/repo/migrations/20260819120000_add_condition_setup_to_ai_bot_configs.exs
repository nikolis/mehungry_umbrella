defmodule Mehungry.Repo.Migrations.AddConditionSetupToAiBotConfigs do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_configs) do
      # "theme" (Month → Week → Day themes) or "condition" (disease-driven)
      add :setup_type, :string, null: false, default: "theme"
      add :condition_id, references(:conditions, on_delete: :nilify_all)
      add :diet_direction, :string
    end

    # A "condition" setup has no theme, so the column can no longer be NOT NULL.
    # The changeset requires :theme only for "theme" setups (validate_setup_fields/1).
    alter table(:ai_bot_configs) do
      modify :theme, :string, null: true, from: {:string, null: false}
    end

    create index(:ai_bot_configs, [:condition_id])
  end
end
