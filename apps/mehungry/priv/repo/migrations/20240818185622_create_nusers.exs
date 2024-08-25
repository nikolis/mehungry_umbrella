defmodule Mehungry.Repo.Migrations.CreateNusers do
  use Ecto.Migration

  def change do
    create table(:nusers) do
      add :email, :string

      timestamps()
    end
  end
end
