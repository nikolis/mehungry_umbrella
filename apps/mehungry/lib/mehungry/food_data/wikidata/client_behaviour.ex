defmodule Mehungry.FoodData.Wikidata.ClientBehaviour do
  @moduledoc """
  Behaviour for the Wikidata species-enrichment fetch, so the live HTTP lookup can be
  swapped for a stub in tests via the `:wikidata_client` config key.
  """

  @doc """
  Resolve a species to its Wikidata facts. Tries `scientific_name` first (best
  disambiguation), then `name`. Returns an enrichment map (any key may be absent):

      %{
        qid: "Q89",
        origin_region: "Central Asia",
        descriptions:   %{"en" => "species of fruit", "el" => "..."},
        wikipedia_urls: %{"en" => "https://en.wikipedia.org/wiki/Apple", "el" => "..."}
      }

  Always returns `{:ok, map}` (possibly `{:ok, %{}}`) — external flakiness is swallowed
  so an enrichment batch never fails on one species.
  """
  @callback fetch(name :: String.t(), scientific_name :: String.t() | nil) ::
              {:ok, map()}
end
