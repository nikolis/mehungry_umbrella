defmodule Mehungry.Repo.Migrations.IngredientTranslationIndexing do
  use Ecto.Migration

  def change do
    create index(
      :ingredient_translations,
      ["lower(name)"],
      name: :ingredient_translations_lower_name_index
    )
  end
end
