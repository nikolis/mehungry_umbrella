defmodule Mehungry.Repo.Migrations.CreateUserProfiles do
  use Ecto.Migration

  def change do
    create table(:user_profiles) do
      add :alias, :string
      add :intro, :text
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:user_profiles, [:user_id])
  end
end
