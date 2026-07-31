defmodule Mehungry.Repo.Migrations.AddAlternativeNameToFoundementalFoodSpecies do
  use Ecto.Migration

  def change do
    alter table(:foundemental_food_species) do
      add :alternative_name, :string
    end
  end
end
