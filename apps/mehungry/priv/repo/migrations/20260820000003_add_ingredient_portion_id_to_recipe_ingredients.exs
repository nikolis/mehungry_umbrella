defmodule Mehungry.Repo.Migrations.AddIngredientPortionIdToRecipeIngredients do
  use Ecto.Migration

  def up do
    alter table(:recipe_ingredients) do
      add :ingredient_portion_id, references(:ingredient_portions, on_delete: :nilify_all)
    end

    create index(:recipe_ingredients, [:ingredient_portion_id])

    # Backfill the new FK from the existing (ingredient_id, measurement_unit_id)
    # pair — the same implicit link the nutrition engine already resolves. Pick
    # the lowest id when several portions share an (ingredient, unit) pair.
    # Gram rows and rows with no matching portion stay NULL (intended).
    execute("""
    UPDATE recipe_ingredients ri
    SET ingredient_portion_id = (
      SELECT MIN(ip.id) FROM ingredient_portions ip
      WHERE ip.ingredient_id = ri.ingredient_id
        AND ip.measurement_unit_id = ri.measurement_unit_id
    )
    WHERE ri.measurement_unit_id IS NOT NULL
    """)
  end

  def down do
    drop index(:recipe_ingredients, [:ingredient_portion_id])

    alter table(:recipe_ingredients) do
      remove :ingredient_portion_id
    end
  end
end
