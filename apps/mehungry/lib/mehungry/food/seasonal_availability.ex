defmodule Mehungry.Food.SeasonalAvailability do
  @moduledoc """
  The core's read seam for **seasonal availability**: which food species are locally
  on the market in a country in a given month.

  The data is produced by the separate seasonality app, which depends on core, so core
  can never call it directly. Instead core defines this behaviour and reads the
  implementation from config:

      config :mehungry, :seasonal_availability, <module>

  Without that config (or when the module is not loaded) the
  `Mehungry.Food.SeasonalAvailability.Noop` default answers "nothing known": no species
  are available and only Greece is offered as a country. This is the same pattern as
  `:notification_dispatcher`.

  The AI meal planner uses `available_ingredient_ids/2` to restrict the fresh-fruit
  snack options to what is in season where the person lives.
  """

  import Ecto.Query, only: [from: 2]

  alias Mehungry.Repo
  alias Mehungry.Food.FoundementalFood

  @doc "Species ids locally on the market in `country` (ISO-2) in `month` (1–12)."
  @callback available_species_ids(country :: String.t(), month :: 1..12) :: MapSet.t()

  @doc "The countries seasonality knows about, as `%{code, name}` maps."
  @callback supported_countries() :: [%{code: String.t(), name: String.t()}]

  @default_country "GR"

  @doc "The country used when a person has not set one."
  def default_country, do: @default_country

  @doc "Species ids locally on the market in `country` in `month`."
  def available_species_ids(country, month) when is_binary(country) and month in 1..12,
    do: impl().available_species_ids(country, month)

  def available_species_ids(_country, _month), do: MapSet.new()

  @doc """
  Ingredient ids curated onto a species that is locally on the market in `country` in
  `month` (through `FoundementalFood`). An ingredient not curated onto any species is
  never included: its season is unknown.
  """
  def available_ingredient_ids(country, month) do
    case available_species_ids(country, month) |> MapSet.to_list() do
      [] ->
        MapSet.new()

      species_ids ->
        from(f in FoundementalFood,
          where: f.foundemental_species_id in ^species_ids,
          select: f.ingredient_id
        )
        |> Repo.all()
        |> MapSet.new()
    end
  end

  @doc "Countries a person can pick, as `%{code, name}` maps."
  def supported_countries, do: impl().supported_countries()

  @doc "The ISO-2 codes of `supported_countries/0`."
  def supported_country_codes, do: Enum.map(supported_countries(), & &1.code)

  defp impl do
    module = Application.get_env(:mehungry, :seasonal_availability, __MODULE__.Noop)
    if Code.ensure_loaded?(module), do: module, else: __MODULE__.Noop
  end

  defmodule Noop do
    @moduledoc "Default `SeasonalAvailability`: knows no seasons, offers only Greece."
    @behaviour Mehungry.Food.SeasonalAvailability

    @impl true
    def available_species_ids(_country, _month), do: MapSet.new()

    @impl true
    def supported_countries, do: [%{code: "GR", name: "Greece"}]
  end
end
