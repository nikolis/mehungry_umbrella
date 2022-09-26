defmodule MehungryServer.Repo.Migrations.CreateMealPlans do
  use Ecto.Migration

  def change do
    create table(:meal_plans) do
      add :title, :string
      add :description, :string
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:meal_plans, [:user_id])
  end
end
