defmodule MehungrySeasonality.ImportObservation do
  @moduledoc """
  Raw **import signal** for one species × country × calendar month: average tonnes
  imported in that month over the `years` window, and the top origin countries with
  their share (`[%{"country" => "TR", "share" => 0.76}]`). Fetched from Eurostat
  Comext; replaced wholesale on every fetch.
  """

  use Ecto.Schema

  schema "seasonality_import_observations" do
    field :foundemental_species_id, :integer
    field :country, :string
    field :month, :integer
    field :tonnes_avg, :float, default: 0.0
    field :origins, {:array, :map}, default: []
    field :years, {:array, :integer}, default: []
    field :retrieved_at, :utc_datetime

    timestamps()
  end
end
