defmodule Mehungry.Repo.Migrations.AddBadgesToRecipes do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      # Derived per-serving nutrient claims (EU NRV: "High in Iron", "Source of
      # Vitamin C", …). Written by Recipes.put_nutrient_info/2 alongside
      # `nutrients`, so it's recomputed on every create/update via the
      # RecipePutNutrientsWorker. Each element is
      # %{"nutrient" => label, "level" => "high"|"source", "percent_nrv" => int}.
      # Filterable via Food.recipes_with_badge/2.
      add :badges, {:array, :map}, null: false, default: []
    end
  end
end
