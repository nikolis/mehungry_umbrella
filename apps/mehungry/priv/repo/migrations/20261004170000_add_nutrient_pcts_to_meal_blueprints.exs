defmodule Mehungry.Repo.Migrations.AddNutrientPctsToMealBlueprints do
  use Ecto.Migration

  # Per-nutrient caloric-percentage thresholds, keyed by nutrient name, alongside
  # the existing `required_nutrients`/`avoid_nutrients` name arrays. A required
  # nutrient is "met" when its share of total calories is >= its threshold; an
  # avoid nutrient is flagged at or above its threshold.
  def change do
    alter table(:meal_blueprints) do
      add :required_nutrient_pcts, :map, default: %{}, null: false
      add :avoid_nutrient_pcts, :map, default: %{}, null: false
    end
  end
end
