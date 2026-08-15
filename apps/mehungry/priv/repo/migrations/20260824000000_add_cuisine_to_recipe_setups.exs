defmodule Mehungry.Repo.Migrations.AddCuisineToRecipeSetups do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_recipe_setups) do
      add :cuisine, :string
    end
  end
end
