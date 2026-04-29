defmodule Mehungry.Repo.Migrations.CreateIngredientUserMeal do
  use Ecto.Migration

  def change do
    create table(:history_ingredient_user_meals) do
      add :ingredient_id, references(:ingredients, on_delete: :restrict)
      add :user_meal_id, references(:history_user_meals, on_delete: :delete_all)
      add :measurement_unit_id, references(:measurement_units, on_delete: :restrict)
      add :quantity, :float
    end

    create index(:history_ingredient_user_meals, [:ingredient_id])
    create index(:history_ingredient_user_meals, [:user_meal_id])
  end
end
