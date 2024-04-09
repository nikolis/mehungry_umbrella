defmodule Mehungry.Repo.Migrations.CreateFoodRestrictionTypes do
  use Ecto.Migration

  def change do
    create table(:food_restriction_types) do
      add :title, :string
      add :alias, :string

      timestamps()
    end
  end
end
