defmodule MehungrySeasonality.LocalObservation do
  @moduledoc """
  Raw **local-production signal** for one species × country × calendar month: in how
  many of the possible weeks (over the `years` window) the country reported a
  producer-side price for the product. Fetched from the EU agri-food portal; replaced
  wholesale on every fetch.
  """

  use Ecto.Schema

  schema "seasonality_local_observations" do
    field :foundemental_species_id, :integer
    field :country, :string
    field :month, :integer
    field :weeks_quoted, :integer, default: 0
    field :weeks_possible, :integer, default: 0
    field :years, {:array, :integer}, default: []
    field :retrieved_at, :utc_datetime

    timestamps()
  end
end
