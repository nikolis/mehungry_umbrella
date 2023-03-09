defmodule Mehungry.Repo.Migrations.CreateBedels do
  use Ecto.Migration

  def change do
    create table(:bedels) do
      add :url, :string
      add :age, :integer

      timestamps()
    end
  end
end
