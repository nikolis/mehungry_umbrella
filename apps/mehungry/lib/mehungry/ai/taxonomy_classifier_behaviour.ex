defmodule Mehungry.AI.TaxonomyClassifierBehaviour do
  @moduledoc """
  Seam for the taxonomy classifier, resolved through the `:taxonomy_classifier`
  app config key (same pattern as `:social_media_publisher`). Tests wire
  `Mehungry.AI.TaxonomyClassifierStub` here.
  """

  @doc """
  Classifies `ingredients` (`[%{id: integer, name: String.t()}]`) into the
  taxonomy `leaves` (`[%{id: integer, slug: String.t(), path: String.t()}]`).

  Returns `{:ok, %{ingredient_id => %{slug: String.t(), confidence: float}}}`
  where every slug is drawn from `leaves`, or `{:error, reason}`.
  """
  @callback classify(ingredients :: [map()], leaves :: [map()]) ::
              {:ok, %{integer() => map()}} | {:error, term()}
end
