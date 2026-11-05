defmodule Mehungry.Repo.Migrations.AddIconToFoundementalFoodSpecies do
  use Ecto.Migration

  def change do
    alter table(:foundemental_food_species) do
      add :icon, :string
    end
  end
end
