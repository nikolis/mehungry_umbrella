defmodule Mehungry.Repo.Migrations.AddNutritionIndexToRecipes do
  use Ecto.Migration

  def up do
    execute("CREATE INDEX recipes_nutrients ON recipes USING GIN(nutrients)")
  end

  def down do
    execute("DROP INDEX recipes_nutrients")
  end
end
