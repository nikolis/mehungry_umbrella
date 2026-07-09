defmodule Mehungry.Repo.Migrations.CreateFoodProducts do
  use Ecto.Migration

  def up do
    create table(:food_products) do
      add :barcode, :string, null: false
      add :name, :string
      add :brands, :string
      add :quantity, :string
      add :countries, {:array, :string}, default: [], null: false
      add :categories_tags, {:array, :string}, default: [], null: false
      add :nutriments, :map, default: %{}
      add :image_url, :string
      add :image_small_url, :string
      add :nutriscore_grade, :string
      add :ecoscore_grade, :string
      add :completeness, :float
      add :off_last_modified_t, :bigint
      add :data_source, :string, default: "open_food_facts"
      add :ingredient_id, references(:ingredients, on_delete: :nilify_all)
      add :ingredient_match_score, :float
      add :ingredient_match_status, :string, default: "unmatched"

      timestamps()
    end

    create unique_index(:food_products, [:barcode])
    create index(:food_products, [:countries], using: "GIN")
    create index(:food_products, [:categories_tags], using: "GIN")
    create index(:food_products, [:ingredient_match_status])
    create index(:food_products, [:ingredient_id])

    execute "CREATE INDEX food_products_name_trgm_idx ON food_products USING gin (name gin_trgm_ops);"

    create table(:food_product_translations) do
      add :name, :string
      add :ingredients_text, :text

      add :food_product_id, references(:food_products, on_delete: :delete_all), null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:food_product_translations, [:food_product_id, :language_name])

    execute "CREATE INDEX food_product_translations_name_trgm_idx ON food_product_translations USING gin (name gin_trgm_ops);"

    create table(:off_sync_state) do
      add :key, :string, null: false
      add :last_processed_file, :string
      add :last_synced_at, :utc_datetime
      add :products_upserted, :integer, default: 0

      timestamps()
    end

    create unique_index(:off_sync_state, [:key])
  end

  def down do
    drop table(:off_sync_state)
    execute "DROP INDEX IF EXISTS food_product_translations_name_trgm_idx;"
    drop table(:food_product_translations)
    execute "DROP INDEX IF EXISTS food_products_name_trgm_idx;"
    drop table(:food_products)
  end
end
