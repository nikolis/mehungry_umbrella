defmodule Mehungry.Repo.Migrations.AddLicenseToRecipes do
  use Ecto.Migration

  # Per-recipe content license notice (e.g. "CC BY-SA 4.0"), shown next to the
  # "Source" credit on the recipe Steps tab. nil for public-domain imports
  # (MyPlate/Gutenberg) and in-app recipes — only populated for sources that
  # carry a reuse obligation, currently UniTools World Recipes (CC BY-SA 4.0),
  # whose ShareAlike term requires the license to travel with the recipe.
  def change do
    alter table(:recipes) do
      add :license, :string
    end
  end
end
