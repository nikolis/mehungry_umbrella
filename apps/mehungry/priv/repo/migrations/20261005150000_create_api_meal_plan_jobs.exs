defmodule Mehungry.Repo.Migrations.CreateApiMealPlanJobs do
  use Ecto.Migration

  def change do
    create table(:api_meal_plan_jobs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :start_date, :date
      add :days, :integer
      add :notes, :text
      add :result, :map
      add :error, :text

      timestamps()
    end

    create index(:api_meal_plan_jobs, [:user_id])
  end
end
