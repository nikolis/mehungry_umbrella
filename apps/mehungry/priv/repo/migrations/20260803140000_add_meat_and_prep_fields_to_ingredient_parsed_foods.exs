defmodule Mehungry.Repo.Migrations.AddMeatAndPrepFieldsToIngredientParsedFoods do
  use Ecto.Migration

  def change do
    alter table(:ingredient_parsed_foods) do
      add :bone_state, :string
      add :grade, :string
      add :fat, :string
      add :portion, {:array, :string}, null: false, default: []
    end
  end
end
