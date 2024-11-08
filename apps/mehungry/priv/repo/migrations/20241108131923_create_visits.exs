defmodule Mehungry.Repo.Migrations.CreateVisits do
  use Ecto.Migration

  def change do
    create table(:visits) do
      add :ip_address, :string
      add :session_key, :string
      add :details, :map

      timestamps()
    end
  end
end
