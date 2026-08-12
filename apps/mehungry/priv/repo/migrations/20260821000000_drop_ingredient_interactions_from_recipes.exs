defmodule Mehungry.Repo.Migrations.DropIngredientInteractionsFromRecipes do
  use Ecto.Migration

  # The stored `ingredient_interactions` column was only ever populated from the
  # recipe's top-level nutrient map, which never surfaces the individual
  # vitamins/minerals the interaction rules key on — so it was always empty.
  # Interactions are now derived on read from the recipe's ingredients via
  # `NutrientInteractions.interactions_for_ingredients/1`.
  def up do
    alter table(:recipes) do
      remove :ingredient_interactions
    end
  end

  def down do
    alter table(:recipes) do
      add :ingredient_interactions, {:array, :map}, default: []
    end
  end
end
