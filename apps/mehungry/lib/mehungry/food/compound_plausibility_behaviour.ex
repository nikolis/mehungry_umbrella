defmodule Mehungry.Food.CompoundPlausibilityBehaviour do
  @moduledoc """
  Seam for the compound-plausibility gate so tests can stub it (config key
  `:compound_plausibility_judge`), mirroring `:taxonomy_classifier` /
  `:social_media_publisher`.
  """

  @doc """
  Judge whether `compound` is plausibly an intrinsic natural dietary constituent of
  `species` — as opposed to a solvent used to extract it, a contaminant, an assay
  reagent, or a measured biological target.

    * `species` — a `%Food.FoundementalFoodSpecies{}` (name + scientific_name)
    * `compound` — a `%Food.Compound{}` (name, synonyms, compound_type)
    * `studies` — the co-occurring `[%Literature.ScientificStudy{}]` (title/abstract),
      the evidence the candidate was scored from

  Returns `{:ok, %{verdict: :plausible | :implausible | :uncertain, reason: String.t()}}`
  or `{:error, term}` (which the gate treats as fail-safe: no auto-promotion).
  """
  @callback judge(species :: struct(), compound :: struct(), studies :: [struct()]) ::
              {:ok, %{verdict: atom(), reason: String.t()}} | {:error, term()}
end
