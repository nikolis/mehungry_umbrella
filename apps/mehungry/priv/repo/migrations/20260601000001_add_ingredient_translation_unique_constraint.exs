defmodule Mehungry.Repo.Migrations.AddIngredientTranslationUniqueConstraint do
  use Ecto.Migration

  def change do
    create unique_index(:ingredient_translations, [:ingredient_id, :language_name])
    # index on name already exists from original migration — add one for translated name lookup
    create index(:ingredient_translations, [:language_name, :name])
  end
end
