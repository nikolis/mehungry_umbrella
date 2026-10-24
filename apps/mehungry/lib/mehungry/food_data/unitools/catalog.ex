defmodule Mehungry.FoodData.UniTools.Catalog do
  @moduledoc """
  The curated list of **UniTools World Recipes** datasets the
  `Mehungry.FoodData.UniToolsImporter` can import from.

  Unlike the public-domain MyPlate/Gutenberg corpora, UniTools is licensed
  **CC BY-SA 4.0** — free to reuse (commercially included) *provided* each
  imported recipe keeps the "UniTools — theunitools.com" credit **and** carries
  the CC BY-SA 4.0 license forward (ShareAlike). The license/attribution/landing
  page are not hardcoded here: they are read from the dataset file's own wrapper
  metadata by `Mehungry.FoodData.UniTools.Decoder`, so if an upstream version
  changes the licence we honour the new one.

  Each dataset is a single bundled JSON file shipped under `priv/` (offline-safe,
  deterministic) — see `Mehungry.FoodData.UniTools.Client`. Adding a dataset is a
  one-line entry here after dropping its file in `priv/unitools/`.
  """

  @datasets [
    %{
      id: "v1",
      title: "UniTools World Recipes",
      # Path relative to the :mehungry app's priv/ dir (Application.app_dir/2).
      path: "unitools/unitools-recipes-v1.json"
    }
  ]

  @doc "Every catalogued dataset."
  def datasets, do: @datasets

  @doc "The dataset with this id (string), or `nil`."
  def get(id) do
    id = to_string(id)
    Enum.find(@datasets, &(&1.id == id))
  end
end
