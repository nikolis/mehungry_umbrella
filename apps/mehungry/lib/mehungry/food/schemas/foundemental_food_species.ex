defmodule Mehungry.Food.FoundementalFoodSpecies do
  @moduledoc """
  A fundamental food species — the botanical/zoological origin a USDA-backed
  ingredient ultimately maps to (e.g. "Apple", "Cattle"). `variety` narrows it
  (e.g. "Gala"); `scientific_name` and `family` are optional taxonomy.

  Its `foundemental_foods` are the concrete USDA ingredients curated onto it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "foundemental_food_species" do
    field :name, :string
    field :variety, :string
    field :alternative_name, :string
    field :scientific_name, :string
    field :family, :string
    field :icon, :string
    # A licence-gated Wikimedia Commons photo, re-hosted on our storage, shown in place
    # of the emoji `icon` on /foods. Written by the species-enrichment sweep only when
    # the Commons licence is reusable (CC0/PD/CC BY/CC BY-SA); the attribution fields
    # travel with it so the credit can always be rendered. See
    # `docs/implementation/science/species_enrichment.md`.
    field :image_url, :string
    field :image_license, :string
    field :image_license_url, :string
    field :image_attribution, :string
    field :image_source_url, :string
    # Curated crosswalk to a FAOSTAT crop/livestock item code — the key the
    # top-producers enrichment (FAOSTAT, CC BY 4.0) joins on. Nullable: many
    # species have no FAOSTAT item (processed, variety-level, non-FAO).
    field :faostat_item_code, :string

    # When true, the species is hidden from every public/consumer surface (/foods
    # browse, search, filter, directory, its detail page, the sitemap, and the
    # mobile API) but stays visible in the admin USDA Schema view for curation.
    field :private, :boolean, default: false

    has_many :foundemental_foods, Mehungry.Food.FoundementalFood,
      foreign_key: :foundemental_species_id

    has_many :translations, Mehungry.Food.FoundementalFoodSpeciesTranslation,
      foreign_key: :foundemental_species_id

    timestamps()
  end

  def changeset(species, attrs) do
    species
    |> cast(attrs, [
      :name,
      :variety,
      :alternative_name,
      :scientific_name,
      :family,
      :icon,
      :image_url,
      :image_license,
      :image_license_url,
      :image_attribution,
      :image_source_url,
      :faostat_item_code,
      :private
    ])
    |> cast_assoc(:translations,
      with: &Mehungry.Food.FoundementalFoodSpeciesTranslation.changeset/2,
      sort_param: :translations_sort,
      drop_param: :translations_drop
    )
    |> validate_required([:name])
    |> unique_constraint([:name, :variety])
  end
end
