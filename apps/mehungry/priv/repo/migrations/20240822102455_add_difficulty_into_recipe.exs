defmodule Mehungry.Repo.Migrations.AddDifficultyIntoRecipe do
  use Ecto.Migration

  def change do
    alter table(:recipes) do 
      add :difficulty, :integer 
    end 
  end
end
