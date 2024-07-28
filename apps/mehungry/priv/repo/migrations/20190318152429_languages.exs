defmodule MehungryServer.Repo.Migrations.Languages do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:languages, primary_key: false) do
      add :name, :string, primary_key: true

      timestamps()
    end

    create unique_index(:languages, [:name])
  end
end
