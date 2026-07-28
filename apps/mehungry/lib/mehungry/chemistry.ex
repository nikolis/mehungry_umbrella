defmodule Mehungry.Chemistry do
  @moduledoc """
  Chemistry context — external chemical-data enrichment for the canonical
  compound registry (`Mehungry.Food.Compounds`).

  PubChem is treated as an external authority, exactly like USDA is for
  ingredients: `Mehungry.Chemistry.PubChem` normalizes a fuzzy name into a stable
  chemical identity (CID, canonical name, formula, SMILES, InChI, synonyms) and
  *syncs it into* `Food.Compounds`. The rest of the application never talks to
  PubChem — it only reads `Food.Compounds`.

  This context owns the two sidecar concerns:

    * `PubChem.RawResponse` (`pubchem_responses`) — an append-only cache of every
      raw PUG REST payload, so the original response is never lost.
    * `CompoundSource` (`compound_sources`) — per-source provenance, so PubChem is
      not hard-coded as the only authority (FooDB/ChEBI/HMDB slot in later).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.Compound
  alias Mehungry.Chemistry.{CompoundSource, PubChem, Resolver}
  alias Mehungry.Chemistry.PubChem.RawResponse

  @doc """
  Resolve a chemical identity into `Food.Compounds`, identifier-first.

  The central ingestion entry point — see `Mehungry.Chemistry.Resolver.resolve/2`.
  """
  defdelegate resolve(input, opts \\ []), to: Resolver

  @doc """
  Resolve a compound *name* via PubChem and sync it into `Food.Compounds`.

  The name-only fallback of the resolver — see
  `Mehungry.Chemistry.PubChem.import_compound/2`.
  """
  defdelegate import_compound(name, opts \\ []), to: PubChem

  # ── Raw response cache (append-only) ──────────────────────────────────────

  @doc "Persist a raw PubChem payload. Append-only — never overwritten."
  def store_raw_response(attrs) do
    %RawResponse{}
    |> RawResponse.changeset(attrs)
    |> Repo.insert()
  end

  @doc "The most recent stored CID for a `name_cids` lookup, or `nil`."
  def latest_resolved_cid(requested_name) do
    Repo.one(
      from r in RawResponse,
        where:
          r.endpoint == "name_cids" and r.requested_name == ^requested_name and not is_nil(r.cid),
        order_by: [desc: r.id],
        limit: 1,
        select: r.cid
    )
  end

  # ── Per-source provenance ─────────────────────────────────────────────────

  @doc "Upsert a compound's provenance row for a source, keyed on `(compound_id, source_type)`."
  def record_compound_source(attrs) do
    %CompoundSource{}
    |> CompoundSource.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:compound_id, :source_type]
    )
  end

  @doc "The provenance row for a compound + source, or `nil`."
  def get_compound_source(compound_id, source_type) do
    Repo.get_by(CompoundSource, compound_id: compound_id, source_type: source_type)
  end

  @doc "All provenance rows for a compound."
  def list_compound_sources(compound_id) do
    Repo.all(
      from s in CompoundSource,
        where: s.compound_id == ^compound_id,
        order_by: [asc: s.source_type]
    )
  end

  @doc """
  The canonical compound already synced from PubChem for `cid`, or `nil`.

  This is the importer's idempotency anchor: the presence of a `pubchem`
  provenance row for the CID means the identity is already in the registry.
  """
  def pubchem_synced_compound(cid) do
    Repo.one(
      from s in CompoundSource,
        join: c in Compound,
        on: c.id == s.compound_id,
        where: s.source_type == "pubchem" and s.external_identifier == ^to_string(cid),
        select: c
    )
  end
end
