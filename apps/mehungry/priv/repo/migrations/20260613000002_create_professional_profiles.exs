defmodule Mehungry.Repo.Migrations.CreateProfessionalProfiles do
  use Ecto.Migration

  def change do
    create table(:professional_profiles) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :specialization, :string, null: false
      add :bio, :text

      timestamps()
    end

    create unique_index(:professional_profiles, [:user_id])
    create index(:professional_profiles, [:specialization])
  end
end
