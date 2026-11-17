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
        wikipedia_urls: %{"en" => "https://en.wikipedia.org/wiki/Apple", "el" => "..."},
        image: %{
          filename: "Foeniculum July 2011-1a.jpg",
          url: "https://.../Foeniculum_July_2011-1a.jpg/800px-...jpg",
          original_url: "https://.../Foeniculum_July_2011-1a.jpg",
          descriptionurl: "https://commons.wikimedia.org/wiki/File:Foeniculum_July_2011-1a.jpg",
          license_code: "cc-by-sa-3.0",
          license_name: "CC BY-SA 3.0",
          license_url: "https://creativecommons.org/licenses/by-sa/3.0",
          artist: "Alvesgaspar",
          restrictions: nil
        }
      }

  The `:image` key (from `P18` + the Commons imageinfo API) is present only when the
  entity has a lead image; the caller still applies a licence allow-list before using
  it. Always returns `{:ok, map}` (possibly `{:ok, %{}}`) — external flakiness is
  swallowed so an enrichment batch never fails on one species.
  """
  @callback fetch(name :: String.t(), scientific_name :: String.t() | nil) ::
              {:ok, map()}
end
