defmodule Mehungry.Repo.Migrations.CreateHistoryFreeFoodUserMeals do
  use Ecto.Migration

  def change do
    create table(:history_free_food_user_meals) do
      add :user_meal_id,
          references(:history_user_meals, on_delete: :delete_all),
          null: false

      # Free-text food name (e.g. "McDonald's Big Mac") — never a Recipe/Ingredient.
      add :name, :string, null: false

      # Resolved total grams logged — the single source of truth for scaling the
      # per-100g nutrients. The controller resolves this from either the grams the
      # client sent, or portion_grams * portions.
      add :grams, :float, null: false

      # Client-supplied per-100g nutrients, stored canonically as
      # %{"<name>" => %{"unit" => ..., "amount" => ...}} (matches recipe.nutrients
      # :map convention; merges by nutrient name in the daily summary).
      add :nutrients_per_100g, :map, null: false

      # Portion metadata — display / round-trip only (portion-mode logging).
      add :portion_name, :string
      add :portion_grams, :float
      add :portions, :float
    end

    create index(:history_free_food_user_meals, [:user_meal_id])
  end
end
