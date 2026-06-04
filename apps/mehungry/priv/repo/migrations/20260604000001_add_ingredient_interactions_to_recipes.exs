defmodule Mehungry.Repo.Migrations.AddIngredientInteractionsToRecipes do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      add :ingredient_interactions, {:array, :map}, default: []
    end
  end
end
