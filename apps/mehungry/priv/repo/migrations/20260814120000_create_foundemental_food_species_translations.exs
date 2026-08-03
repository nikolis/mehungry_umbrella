defmodule Mehungry.Repo.Migrations.CreateFoundementalFoodSpeciesTranslations do
  use Ecto.Migration

  def change do
    create table(:foundemental_food_species_translations) do
      add :name, :string
      add :description, :string
      add :url, :string

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all)

      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all)

      timestamps()
    end

    create index(:foundemental_food_species_translations, [:name])

    create unique_index(:foundemental_food_species_translations, [
             :foundemental_species_id,
             :language_name
           ])

    create index(:foundemental_food_species_translations, [:language_name, :name])
  end
end
