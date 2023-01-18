defmodule MehungryApi.Repo.Migrations.CreateHistoryUserMeals do
  use Ecto.Migration

  def change do
    create table(:history_user_meals) do
      add :title, :string
      add :start_dt, :naive_datetime
      add :end_dt, :naive_datetime

      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:history_user_meals, [:user_id])
  end
end
