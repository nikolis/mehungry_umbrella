defmodule Mehungry.Repo.Migrations.AddPartAndDismembermentToIngredientParsedFoods do
  use Ecto.Migration

  def change do
    alter table(:ingredient_parsed_foods) do
      add :part, :string
      add :dismemberment, :string
    end
  end
end
