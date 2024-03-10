defmodule Mehungry.Repo.Migrations.CreateNutrientTable do
  use Ecto.Migration

  def change do
    create table(:nutrients) do
      add :name, :string
      add :description, :string
      add :alternate_name, :string
      add :family, :string

      # FoodData Central Data Types  https://fdc.nal.usda.gov/download-datasets.html
      add :rank, :integer
      add :number, :string
      add :reference_id, :integer

      add :measurement_unit_id, references(:measurement_units)
      timestamps()
    end

    create unique_index(:nutrients, [:name, :measurement_unit_id])
  end
end
