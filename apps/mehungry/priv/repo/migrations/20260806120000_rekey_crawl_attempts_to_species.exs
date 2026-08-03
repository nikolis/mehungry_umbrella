defmodule Mehungry.Repo.Migrations.RekeyCrawlAttemptsToSpecies do
  use Ecto.Migration

  @moduledoc """
  Re-keys the literature crawl ledger from ingredient to foundemental food
  species. The crawl unit is now the species (crawled by its curated
  `scientific_name`), so `literature_crawl_attempts` is keyed on
  `(foundemental_species_id, search_term)`.

  The ledger is a rebuildable dedup/watermark table — clearing it just forces a
  fresh crawl — so we truncate rather than migrate old ingredient-keyed rows.
  """

  def up do
    execute("DELETE FROM literature_crawl_attempts")

    drop unique_index(:literature_crawl_attempts, [:ingredient_id, :search_term])

    alter table(:literature_crawl_attempts) do
      remove :ingredient_id

      add :foundemental_species_id,
          references(:foundemental_food_species, on_delete: :delete_all),
          null: false
    end

    create index(:literature_crawl_attempts, [:foundemental_species_id])
    create unique_index(:literature_crawl_attempts, [:foundemental_species_id, :search_term])
  end

  def down do
    execute("DELETE FROM literature_crawl_attempts")

    drop unique_index(:literature_crawl_attempts, [:foundemental_species_id, :search_term])
    drop index(:literature_crawl_attempts, [:foundemental_species_id])

    alter table(:literature_crawl_attempts) do
      remove :foundemental_species_id
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
    end

    create unique_index(:literature_crawl_attempts, [:ingredient_id, :search_term])
  end
end
