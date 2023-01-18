defmodule Mehungry.Repo.Migrations.ModifyRecipeTable do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      add :list_image_url, :string
      add :detail_image_url, :string
    end

  end
end
