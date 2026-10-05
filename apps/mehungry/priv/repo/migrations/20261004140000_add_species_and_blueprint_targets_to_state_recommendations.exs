defmodule Mehungry.Repo.Migrations.AddSpeciesAndBlueprintTargetsToStateRecommendations do
  use Ecto.Migration

  # Broaden the decoupled advice store's target beyond compound/nutrient/free-text:
  # a suggestion in /professional/health can now also resolve directly to a
  # `FoundementalFoodSpecies` (matched by name or scientific name) or a public
  # `MealBlueprint` (matched by name). Both are nullable — exactly one target
  # column is set per row (see the schema's `validate_has_target/1`).
  def change do
    alter table(:condition_state_recommendations) do
      add :species_id,
          references(:foundemental_food_species, on_delete: :nilify_all)

      add :blueprint_id, references(:meal_blueprints, on_delete: :nilify_all)
    end

    create index(:condition_state_recommendations, [:species_id])
    create index(:condition_state_recommendations, [:blueprint_id])
  end
end
