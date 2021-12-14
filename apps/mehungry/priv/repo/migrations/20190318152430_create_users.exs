defmodule MehungryServer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :first_name, :string
      add :last_name, :string
      add :facebook_id, :string

      timestamps()
    end

    create unique_index(:users, [:facebook_id])
  end
end
