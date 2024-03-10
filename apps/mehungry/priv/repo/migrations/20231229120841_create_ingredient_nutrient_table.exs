defmodule Mehungry.Repo.Migrations.CreateIngredientNutrientTable do
  use Ecto.Migration

  def change do
    create table(:ingredient_nutrients) do
      add :median, :float
      add :amount, :float
      add :data_points, :integer
      add :type_, :string

      add :ingredient_id, references(:ingredients)
      add :nutrient_id, references(:nutrients)
      timestamps()
    end
  end
end
