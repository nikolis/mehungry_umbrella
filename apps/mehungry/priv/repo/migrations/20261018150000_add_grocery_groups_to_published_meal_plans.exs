defmodule Mehungry.Repo.Migrations.AddGroceryGroupsToPublishedMealPlans do
  use Ecto.Migration

  def change do
    alter table(:published_meal_plans) do
      # Grocery list grouped into shopping aisles. Old rows keep the flat
      # `grocery` list (the view falls back to it); re-publishing fills this.
      add :grocery_groups, {:array, :map}, null: false, default: []
    end
  end
end
