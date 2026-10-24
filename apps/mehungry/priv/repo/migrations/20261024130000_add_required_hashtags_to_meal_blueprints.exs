defmodule Mehungry.Repo.Migrations.AddRequiredHashtagsToMealBlueprints do
  use Ecto.Migration

  def change do
    alter table(:meal_blueprints) do
      # Recipe hashtags a plan generated from this blueprint must carry (e.g.
      # ["raw"]). The general lever behind preparation-method diet patterns like
      # Raw Vegan / Raw Vegetarian, enforced in MealPlanAgent.search_catalog via
      # Food.recipe_ids_with_all_hashtags/2. Mirrors the other free-text array
      # tag fields (preferred_foods/avoid_foods).
      add :required_hashtags, {:array, :string}, null: false, default: []
    end
  end
end
