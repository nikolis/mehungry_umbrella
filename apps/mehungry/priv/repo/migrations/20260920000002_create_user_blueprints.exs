defmodule Mehungry.Repo.Migrations.CreateUserBlueprints do
  use Ecto.Migration

  def change do
    create table(:user_blueprints) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :blueprint_id, references(:meal_blueprints, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:user_blueprints, [:user_id])
    create index(:user_blueprints, [:blueprint_id])
    create unique_index(:user_blueprints, [:user_id, :blueprint_id])
  end
end
