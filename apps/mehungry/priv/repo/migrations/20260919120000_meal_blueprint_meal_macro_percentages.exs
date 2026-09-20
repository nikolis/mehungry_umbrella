defmodule Mehungry.Repo.Migrations.MealBlueprintMealMacroPercentages do
  use Ecto.Migration

  # Replaces the per-meal absolute-gram targets (protein min/max, sugar/carb max)
  # with a percentage macro split — protein/carbs/fats — that always totals 100%
  # (default 30/40/30).
  def up do
    alter table(:meal_blueprint_meals) do
      add :protein_pct, :integer, default: 30, null: false
      add :carbs_pct, :integer, default: 40, null: false
      add :fats_pct, :integer, default: 30, null: false

      remove :protein_min_g
      remove :protein_max_g
      remove :sugar_max_g
      remove :carbs_max_g
    end
  end

  def down do
    alter table(:meal_blueprint_meals) do
      add :protein_min_g, :float
      add :protein_max_g, :float
      add :sugar_max_g, :float
      add :carbs_max_g, :float

      remove :protein_pct
      remove :carbs_pct
      remove :fats_pct
    end
  end
end
