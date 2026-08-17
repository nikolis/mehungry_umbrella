defmodule Mehungry.Repo.Migrations.AddIngredientPortionToIngredientUserMeals do
  use Ecto.Migration

  # Calendar ingredient meals now pick a human-meaningful ingredient portion
  # ("1 medium banana", "1 cup") instead of only a gram measurement unit, so a
  # logged ingredient carries the portion it resolves to (nil for gram-family
  # rows). `measurement_unit_id` is kept and no longer required at the DB level:
  # a row now resolves to either a measurement unit or a portion (see
  # `IngredientUserMeal.changeset/2`), mirroring `recipe_ingredients`.
  def change do
    alter table(:history_ingredient_user_meals) do
      add :ingredient_portion_id, references(:ingredient_portions, on_delete: :nilify_all)
    end

    create index(:history_ingredient_user_meals, [:ingredient_portion_id])
  end
end
