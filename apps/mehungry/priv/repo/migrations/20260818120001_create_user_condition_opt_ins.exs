defmodule Mehungry.Repo.Migrations.CreateUserConditionOptIns do
  use Ecto.Migration

  def change do
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
