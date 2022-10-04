defmodule Mehungry.Repo.Migrations.CreateDemographics do
  use Ecto.Migration

  def change do
    create table(:demographics) do
      add :capacity, :string
      add :year_of_birth, :integer
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create unique_index(:demographics, [:user_id])
  end
end
