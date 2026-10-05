defmodule Mehungry.Repo.Migrations.AddNutrientModesToMealBlueprints do
  use Ecto.Migration

  # Per-nutrient threshold *mode*, keyed by nutrient name, alongside the value in
  # `*_nutrient_pcts`: "pct" (value = % of the day's calories, the default) or
  # "amount" (value = a per-day total in the nutrient's own unit, e.g. 2300 mg
  # Sodium). A missing entry means "pct".
  def change do
    alter table(:meal_blueprints) do
      add :required_nutrient_modes, :map, default: %{}, null: false
      add :avoid_nutrient_modes, :map, default: %{}, null: false
    end
  end
end
