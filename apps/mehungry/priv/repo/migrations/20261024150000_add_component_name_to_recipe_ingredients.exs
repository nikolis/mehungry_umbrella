defmodule Mehungry.Repo.Migrations.AddComponentNameToRecipeIngredients do
  use Ecto.Migration

  # Additive, nullable column: lets a recipe ingredient be grouped under a named
  # part/component (e.g. "Salad" vs "Dressing"). `nil` means ungrouped — every
  # existing row stays ungrouped and renders flat, exactly as before. Steps carry
  # the same label in the already-existing embedded `Step.title` field (no column
  # needed — steps are jsonb-embedded on `recipes`).
  def change do
    alter table(:recipe_ingredients) do
      add :component_name, :string
    end
  end
end
