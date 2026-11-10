defmodule Mehungry.Repo.Migrations.AddPrivateToFoundementalFoodSpecies do
  use Ecto.Migration

  # A private species is hidden from every public/consumer surface (the /foods
  # browse feed, name search, compound filter, A–Z directory, its detail page,
  # the sitemap, and the mobile API) while staying visible in the admin USDA
  # Schema view for curation. Defaults to public so existing rows are unchanged.
  def change do
    alter table(:foundemental_food_species) do
      add :private, :boolean, null: false, default: false
    end
  end
end
