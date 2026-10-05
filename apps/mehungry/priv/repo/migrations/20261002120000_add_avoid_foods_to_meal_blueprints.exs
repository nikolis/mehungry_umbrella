defmodule Mehungry.Repo.Migrations.AddAvoidFoodsToMealBlueprints do
  use Ecto.Migration

  # Blueprint-level free-text list of foods to exclude (mirrors `preferred_foods`).
  # The defining lever for avoidance diets like Low-FODMAP (no onion/garlic/wheat…).
  def change do
    alter table(:meal_blueprints) do
      add :avoid_foods, {:array, :string}, default: [], null: false
    end
  end
end
