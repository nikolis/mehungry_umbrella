defmodule MehungrySeasonality.Core do
  @moduledoc """
  **The only door out of the seasonality app.** Every dependency on the core
  `:mehungry` app is listed in this one file: the shared Repo, the shared PubSub, and
  **read-only** access to food species. No other module in this app may reference a
  `Mehungry.*` module (enforced by `MehungrySeasonality.BoundaryTest`).

  Species are handed to the rest of the app as plain `%{id, name, variety}` maps, so
  nothing here depends on the shape of the core schema beyond those three fields.

  The traffic also runs the other way through this file: it implements core's
  `Mehungry.Food.SeasonalAvailability` behaviour, wired by
  `config :mehungry, :seasonal_availability, MehungrySeasonality.Core`, so the core
  app's meal planner can read seasons without ever naming this app.
  """

  @behaviour Mehungry.Food.SeasonalAvailability

  @type species :: %{id: integer(), name: String.t(), variety: String.t() | nil}

  @impl Mehungry.Food.SeasonalAvailability
  def available_species_ids(country, month),
    do: MehungrySeasonality.available_species_ids(country, month)

  @impl Mehungry.Food.SeasonalAvailability
  def supported_countries, do: MehungrySeasonality.supported_countries()

  @doc "The shared Ecto repo."
  def repo, do: Mehungry.Repo

  @doc "The shared PubSub server name."
  def pubsub, do: Mehungry.PubSub

  @doc "Every food species (admin scope), as slim maps ordered by name."
  @spec list_species() :: [species()]
  def list_species do
    Mehungry.Food.list_foundemental_species() |> Enum.map(&slim/1)
  end

  @doc "One species as a slim map, or nil."
  @spec get_species(integer()) :: species() | nil
  def get_species(id) do
    case Mehungry.Food.get_foundemental_species(id) do
      nil -> nil
      species -> slim(species)
    end
  end

  @doc "An `%{id => species}` map of slim species for the given ids."
  @spec species_by_ids([integer()]) :: %{integer() => species()}
  def species_by_ids([]), do: %{}

  def species_by_ids(ids) do
    ids
    |> Mehungry.Food.species_by_ids()
    |> Map.new(fn {id, species} -> {id, slim(species)} end)
  end

  defp slim(species), do: %{id: species.id, name: species.name, variety: species.variety}
end
