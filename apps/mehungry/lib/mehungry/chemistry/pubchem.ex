defmodule Mehungry.Chemistry.PubChem do
  @moduledoc """
  Name-based PubChem import — the *fallback* path of `Mehungry.Chemistry.Resolver`
  for a data source that supplies a chemical **name** with no normalized
  identifier.

  It turns a fuzzy compound name ("oxalate", "oxalic acid", "ethanedioic acid")
  into a stable chemical identity and syncs it into the canonical
  `Mehungry.Food.Compounds` registry by delegating to the resolver — which anchors
  the identity on the resolved PubChem CID, records its cross-database identifiers
  (`compound_identifiers`), and retains every raw PUG REST payload append-only in
  `pubchem_responses`.

  Prefer `Mehungry.Chemistry.Resolver.resolve/2` with a normalized identifier
  (e.g. a MeSH id) when the source has one; `name_to_cids/1` is only the anchor
  when it does not.
  """

  alias Mehungry.Chemistry.Resolver

  @doc """
  Resolve `name` via PubChem and sync the identity into `Food.Compounds`.

  Options are forwarded to `Mehungry.Chemistry.Resolver.resolve/2`
  (`:compound_type`, `:refresh`). Returns `{:ok, %Mehungry.Food.Compound{}}`,
  `{:error, :not_found}` when PubChem knows no CID for the name, or
  `{:error, reason}` on a transient failure.
  """
  @spec import_compound(String.t(), keyword()) ::
          {:ok, Mehungry.Food.Compound.t()} | {:error, :not_found | term()}
  def import_compound(name, opts \\ []) do
    Resolver.resolve(%{name: String.trim(name)}, Keyword.put_new(opts, :source, "pubchem"))
  end
end
