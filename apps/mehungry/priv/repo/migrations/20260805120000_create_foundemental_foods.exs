defmodule Mehungry.Repo.Migrations.CreateFoundementalFoods do
  use Ecto.Migration

  def change do
    create table(:foundemental_food_species) do
      add :name, :string, null: false
      add :variety, :string
      add :scientific_name, :string
      add :family, :string

      timestamps()
    end

    create unique_index(:foundemental_food_species, [:name, :variety])

    create table(:foundemental_foods) do
      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false

      add :usda_name, :string, null: false
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:foundemental_foods, [:foundemental_species_id])
    create unique_index(:foundemental_foods, [:ingredient_id])
  end
end
