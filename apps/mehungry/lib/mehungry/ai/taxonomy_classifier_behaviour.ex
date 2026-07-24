defmodule Mehungry.AI.TaxonomyClassifierBehaviour do
  @moduledoc """
  Seam for the taxonomy classifier so tests can stub it (config key
  `:taxonomy_classifier`), mirroring `:instagram_client` / `:social_media_publisher`.
  """

  @doc """
  Classifies ingredients into taxonomy leaves.

    * `ingredients` — `[%{id: integer, name: String.t()}]`
    * `leaves` — `[%{id: integer, slug: String.t(), path: String.t()}]`

  Returns `{:ok, [%{ingredient_id, taxonomy_node_id, confidence}]}` or
  `{:error, term}`.
  """
  @callback classify(ingredients :: [map()], leaves :: [map()]) ::
              {:ok, [map()]} | {:error, term()}
end
