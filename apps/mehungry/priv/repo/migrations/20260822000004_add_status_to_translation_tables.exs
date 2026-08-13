defmodule Mehungry.Repo.Migrations.AddStatusToTranslationTables do
  use Ecto.Migration

  # The six translation tables that predate the translation hub. New tables
  # (compound/condition/nutrient) already carry these columns.
  @tables ~w(
    recipe_translations
    ingredient_translations
    category_translations
    measurement_unit_translations
    foundemental_food_species_translations
    food_product_translations
  )a

  def change do
    for table <- @tables do
      alter table(table) do
        # Existing rows are hand-curated content — treat them as trusted.
        add :status, :string, default: "verified", null: false
        add :verified_at, :utc_datetime
        add :verified_by_id, references(:users, on_delete: :nilify_all)
      end

      create index(table, [:language_name, :status])
    end
  end
end
