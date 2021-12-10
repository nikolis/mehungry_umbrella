defmodule MehungryServer.Repo.Migrations.Languages do
  use Ecto.Migration

  def change do
    create table(:languages) do
      add :name, :string

      timestamps()
    end

    create index(:languages, [:name])
  end
end
