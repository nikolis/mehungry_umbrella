defmodule Mehungry.Repo.Migrations.AddImageToFoundementalFoodSpecies do
  use Ecto.Migration

  def change do
    alter table(:foundemental_food_species) do
      # A licence-gated Wikimedia Commons photo re-hosted on our storage, shown in
      # place of the emoji icon. All five travel together so the attribution can
      # always be rendered next to the image.
      add :image_url, :string
      add :image_license, :string
      add :image_license_url, :string
      add :image_attribution, :string
      add :image_source_url, :string
    end
  end
end
