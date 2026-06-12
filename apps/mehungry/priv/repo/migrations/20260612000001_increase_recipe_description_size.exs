defmodule Mehungry.Repo.Migrations.IncreaseRecipeDescriptionSize do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      modify :description, :text
    end
  end
end
