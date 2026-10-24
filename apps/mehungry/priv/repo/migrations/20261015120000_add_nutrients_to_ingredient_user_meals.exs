defmodule Mehungry.Repo.Migrations.AddNutrientsToIngredientUserMeals do
  use Ecto.Migration

  # Denormalized, write-time nutrient tree for a logged ingredient meal, mirroring
  # `recipes.nutrients`. Lets the calendar read a stored map instead of rebuilding
  # the hierarchical tree per ingredient on every page load. No GIN index (unlike
  # recipes): the calendar only ever queries these rows by user_id + date range,
  # never by nutrient content, so an index would be pure write cost.
  def up do
    alter table(:history_ingredient_user_meals) do
      add :nutrients, :map, default: %{}
    end
  end

  def down do
    alter table(:history_ingredient_user_meals) do
      remove :nutrients
    end
  end
end
