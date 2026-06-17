defmodule Mehungry.Repo.Migrations.AddNutrientDataSourceToIngredients do
  use Ecto.Migration

  def change do
    alter table(:ingredients) do
      add :nutrient_data_source, :string, null: true
    end
  end
end
