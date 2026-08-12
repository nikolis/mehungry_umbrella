defmodule Mehungry.Repo.Migrations.AddNutritionMetaToRecipes do
  use Ecto.Migration

  # Schema-only migration.
  #
  # This originally back-filled `nutrients` by calling
  # `Mehungry.Food.RecipeUtils.get_nutrients/1` in a loop. That on-the-fly
  # calculation path was removed (see `docs/nutrition_calculation.md`), and
  # calling application code from a migration is fragile besides. The columns are
  # populated by the normal write path (`Mehungry.RecipePutNutrientsWorker`),
  # which runs on every recipe create/update, and can be back-filled on demand via
  # `Mehungry.Food.Nutrients.start_full_recalculation_run/0`, so the loop was
  # dropped. On already-migrated databases this migration has no further effect.

  def down do
    alter table(:recipes) do
      remove :nutrients
      remove :primary_nutrients_size
    end
  end

  def up do
    alter table(:recipes) do
      add :nutrients, :map, default: %{}
      add :primary_nutrients_size, :integer
    end
  end
end
