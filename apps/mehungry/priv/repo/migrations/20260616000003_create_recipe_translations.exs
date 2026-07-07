defmodule Mehungry.Repo.Migrations.CreateRecipeTranslations do
  use Ecto.Migration

  def change do
    create table(:recipe_translations) do
      add :recipe_id, references(:recipes, on_delete: :delete_all), null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :restrict), null: false

      add :title, :string
      add :description, :text
      add :steps, {:array, :map}, default: []

      timestamps()
    end

    create unique_index(:recipe_translations, [:recipe_id, :language_name])
    create index(:recipe_translations, [:recipe_id])
  end
end
