defmodule Mehungry.Repo.Migrations.DropUserConditionOptIns do
  use Ecto.Migration

  # Removes the end-user health-condition opt-in feature. These rows are
  # special-category (health) data under GDPR Art. 9 that the product no longer
  # collects — condition/dietary guidance is now gated to the nutritionist and
  # admin surfaces only. Dropping the table permanently deletes the stored
  # opt-ins. See docs/implementation/legal/legal_review_2026-10.md (R1/R3).

  def up do
    drop_if_exists table(:user_condition_opt_ins)
  end

  def down do
    create table(:user_condition_opt_ins) do
      add :user_profile_id, references(:user_profiles, on_delete: :delete_all), null: false
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:user_condition_opt_ins, [:user_profile_id])
    create index(:user_condition_opt_ins, [:condition_id])

    create unique_index(:user_condition_opt_ins, [:user_profile_id, :condition_id],
             name: :user_condition_opt_ins_profile_condition_index
           )
  end
end
