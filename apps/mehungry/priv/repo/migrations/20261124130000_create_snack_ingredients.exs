defmodule Mehungry.Repo.Migrations.CreateSnackIngredients do
  use Ecto.Migration

  # Admin-curated ingredients the AI meal-plan assistant may offer as snacks,
  # grouped by `kind` (only "dried_nut" today). See
  # docs/implementation/food/snack_ingredients.md.
  def change do
    create table(:snack_ingredients) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "dried_nut"
      add :added_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:snack_ingredients, [:ingredient_id, :kind])
    create index(:snack_ingredients, [:kind])
  end
end
