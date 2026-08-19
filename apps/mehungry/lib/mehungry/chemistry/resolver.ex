defmodule Mehungry.Chemistry.Resolver do
  @moduledoc """
  The single, identifier-first entry point for syncing a chemical identity into the
  canonical `Mehungry.Food.Compounds` registry.

  Ingestion sources (PubTator, literature, manual) call the resolver rather than
  talking to PubChem directly. Given whatever identity a source carries, it:

    1. **looks the compound up by identifier** — `(namespace, identifier)`, e.g. the
       MeSH id a PubTator annotation carries — and returns it if already known;
    2. otherwise **cross-resolves additional identifiers** best-effort against
       PubChem (CID, ChEBI, CAS, InChIKey) plus structural properties (formula,
       SMILES, InChI, IUPAC name);
    3. **populates or updates** the `Compound` and its `compound_identifiers` rows,
       recording provenance, and returns the canonical `%Compound{}`.

  Identifiers — not names — are the stable currency, so lookup/dedup is by
  identifier. `Chemistry.PubChem.Client.name_to_cids/1` is used only as a
  cross-reference mechanism (and, for a source that supplies a *name* with no
  normalized identifier, as the sole fallback anchor).

  Guarantees mirror the old PubChem importer: idempotent (a known identifier
  performs no HTTP), cached (`:pubchem_cache` in front of the `pubchem_responses`
  ledger), and history-preserving (every raw payload is stored append-only).
  """

  alias Mehungry.Food
  alias Mehungry.Chemistry
  alias Mehungry.Chemistry.PubChem.Client

  @cache :pubchem_cache
  # Cap how many PubChem synonyms we copy onto the canonical row (relevance-ordered);
  # the full list is always retained in the raw payload.
  @max_synonyms 25
  @chebi_pattern ~r/^CHEBI:\d+$/
  @cas_pattern ~r/^\d{2,7}-\d{2}-\d$/

  @doc """
  Resolve an incoming chemical identity into the canonical registry.

  `input` is a map (string or atom keys) carrying any of:

    * `:namespace` + `:identifier` — a normalized external id (e.g. `"mesh"` /
      `"D000082"`). When present this is the primary identity anchor.
    * `:name` — a chemical name / surface form; the fallback anchor and the term
      used to cross-resolve a PubChem CID.

  Options:

    * `:compound_type` — domain class for a *newly created* compound (default
      `"other"`; never overwrites an existing compound's type).
    * `:source` — who asserted the seeding identifier (default `"chemistry"`).
    * `:refresh` — re-fetch and re-enrich even when the identifier is already known.

  Returns `{:ok, %Mehungry.Food.Compound{}}`, `{:error, :not_found}` when nothing
  resolvable was found, or `{:error, reason}` on a transient failure.
  """
  @spec resolve(map(), keyword()) ::
          {:ok, Mehungry.Food.Compound.t()} | {:error, :not_found | term()}
  def resolve(input, opts \\ []) do
    seed = seed(input)
    name = name(input)
    known = seed && Food.get_compound_by_identifier(elem(seed, 0), elem(seed, 1))

    cond do
      known && not Keyword.get(opts, :refresh, false) ->
        {:ok, known}

      seed || (is_binary(name) and name != "") ->
        resolve_and_sync(seed, name, opts)

      true ->
        {:error, :not_found}
    end
  end

  # ── resolution + sync ─────────────────────────────────────────────────────

  defp resolve_and_sync(seed, name, opts) do
    case anchor_cid(seed, name) do
      {:ok, cid} ->
        sync_or_return(anchored_compound(seed, cid), seed, name, cid, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Idempotency: an identity we already hold performs no enrichment HTTP, but a
  # *new* seed anchor (e.g. a MeSH id reaching a compound first found by name) is
  # still attached. A `:refresh`, or an unknown identity, fetches PubChem and syncs.
  defp sync_or_return(existing, seed, name, cid, opts) do
    if existing && not Keyword.get(opts, :refresh, false) do
      {:ok, attach_seed(existing, seed, opts)}
    else
      with {:ok, resolution} <- resolve_details(cid) do
        sync(seed, name, resolution, opts)
      end
    end
  end

  # Record the seed identifier on an already-known compound without re-fetching
  # PubChem. Its canonical identity is already established, so the seed is an
  # additional cross-reference rather than a new primary.
  defp attach_seed(compound, nil, _opts), do: compound

  defp attach_seed(compound, {ns, id}, opts) do
    Food.upsert_compound_identifier(%{
      compound_id: compound.id,
      namespace: ns,
      identifier: to_string(id),
      is_primary: false,
      source: Keyword.get(opts, :source, "chemistry")
    })

    compound
  end

  # Resolve the anchoring PubChem CID. A MeSH-seeded compound PubChem cannot map to
  # a CID still resolves (identity = the seed alone → `{:ok, nil}`); a name-only
  # input with no CID has no anchor and is `:not_found`.
  defp anchor_cid(seed, name) do
    case seed_cid(seed) do
      cid when is_integer(cid) ->
        {:ok, cid}

      nil ->
        case resolve_cid(name) do
          {:ok, cid} -> {:ok, cid}
          {:error, :not_found} when not is_nil(seed) -> {:ok, nil}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # The compound already anchored to this identity (seed id → PubChem CID), or nil.
  defp anchored_compound(seed, cid) do
    (seed && Food.get_compound_by_identifier(elem(seed, 0), elem(seed, 1))) ||
      (cid && Food.get_compound_by_identifier("pubchem", cid))
  end

  # Fetch the PubChem cross-references / properties for a CID. A seed with no CID
  # yields an empty set — its identity is the seed identifier alone.
  defp resolve_details(nil), do: {:ok, empty_resolution()}
  defp resolve_details(cid), do: enrich_from_cid(cid)

  defp enrich_from_cid(cid) do
    with {:ok, props, props_raw, props_meta} <- Client.properties(cid),
         {:ok, syns, syns_raw, syns_meta} <- Client.synonyms(cid) do
      {:ok, props_row} = store_response("properties", %{cid: cid}, props_raw, props_meta)
      store_response("synonyms", %{cid: cid}, syns_raw, syns_meta)

      {:ok,
       %{
         cid: cid,
         canonical_name: props.title,
         synonyms: Enum.take(syns, @max_synonyms),
         properties: structural_properties(props),
         inchikey: blank_to_nil(props.inchikey),
         chebi: Enum.find(syns, &Regex.match?(@chebi_pattern, &1)),
         cas: Enum.find(syns, &Regex.match?(@cas_pattern, &1)),
         raw_response_id: props_row.id
       }}
    end
  end

  defp empty_resolution do
    %{
      cid: nil,
      canonical_name: nil,
      synonyms: [],
      properties: %{},
      inchikey: nil,
      chebi: nil,
      cas: nil,
      raw_response_id: nil
    }
  end

  defp sync(seed, name, resolution, opts) do
    canonical_name = resolution.canonical_name || name || seed_identifier(seed)
    compound_type = Keyword.get(opts, :compound_type, "other")
    source = Keyword.get(opts, :source, "chemistry")

    with {:ok, compound} <- upsert_compound(seed, resolution, canonical_name, compound_type, name) do
      write_identifiers(compound, seed, resolution, source)
      maybe_record_provenance(compound, resolution)
      {:ok, compound}
    end
  end

  # Converge onto an existing compound (by seed id → pubchem cid → name) before
  # creating a new one, so the same molecule reached by different anchors is one row.
  defp upsert_compound(seed, resolution, canonical_name, compound_type, name) do
    existing =
      (seed && Food.get_compound_by_identifier(elem(seed, 0), elem(seed, 1))) ||
        (resolution.cid && Food.get_compound_by_identifier("pubchem", resolution.cid)) ||
        Food.get_compound_by_name(canonical_name)

    base = %{
      name: canonical_name,
      compound_type: compound_type,
      synonyms: compound_synonyms(name, resolution.synonyms),
      properties: resolution.properties
    }

    case existing do
      nil -> Food.upsert_compound(base)
      compound -> Food.enrich_compound(compound, base)
    end
  end

  # The seed identifier is primary; PubChem CID is primary only on the name-only
  # path (no seed). Every discovered identifier is upserted on its natural key.
  defp write_identifiers(compound, seed, resolution, source) do
    seed_rows =
      case seed do
        {ns, id} ->
          [%{namespace: ns, identifier: to_string(id), is_primary: true, source: source}]

        nil ->
          []
      end

    cross_rows =
      [
        identifier_row("pubchem", resolution.cid, is_nil(seed), "pubchem"),
        identifier_row("chebi", resolution.chebi, false, "pubchem"),
        identifier_row("cas", resolution.cas, false, "pubchem"),
        identifier_row("inchikey", resolution.inchikey, false, "pubchem")
      ]
      |> Enum.reject(&is_nil/1)

    (seed_rows ++ cross_rows)
    |> Enum.each(fn row ->
      Food.upsert_compound_identifier(Map.put(row, :compound_id, compound.id))
    end)
  end

  defp identifier_row(_namespace, nil, _primary, _source), do: nil
  defp identifier_row(_namespace, "", _primary, _source), do: nil

  defp identifier_row(namespace, identifier, is_primary, source) do
    %{
      namespace: namespace,
      identifier: to_string(identifier),
      is_primary: is_primary,
      source: source
    }
  end

  defp maybe_record_provenance(_compound, %{cid: nil}), do: :ok

  defp maybe_record_provenance(compound, %{cid: cid, raw_response_id: raw_response_id}) do
    Chemistry.record_compound_source(%{
      compound_id: compound.id,
      source_type: "pubchem",
      external_identifier: to_string(cid),
      last_synced_at: now(),
      raw_response_id: raw_response_id
    })

    :ok
  end

  # ── name → CID resolution (two-layer cache) ───────────────────────────────

  # A seed already in the pubchem namespace *is* the CID — no lookup needed.
  defp seed_cid({"pubchem", identifier}) do
    case Integer.parse(to_string(identifier)) do
      {cid, _} -> cid
      :error -> nil
    end
  end

  defp seed_cid(_), do: nil

  defp resolve_cid(nil), do: {:error, :not_found}

  defp resolve_cid(name) do
    normalized = name |> String.trim() |> String.downcase()

    case Cachex.get(@cache, {:name, normalized}) do
      {:ok, :not_found} -> {:error, :not_found}
      {:ok, cid} when is_integer(cid) -> {:ok, cid}
      _ -> resolve_cid_uncached(normalized)
    end
  end

  defp resolve_cid_uncached(normalized) do
    case Chemistry.latest_resolved_cid(normalized) do
      cid when is_integer(cid) ->
        Cachex.put(@cache, {:name, normalized}, cid)
        {:ok, cid}

      nil ->
        fetch_cid(normalized)
    end
  end

  defp fetch_cid(normalized) do
    case Client.name_to_cids(normalized) do
      {:ok, cid, raw, meta} ->
        store_response("name_cids", %{requested_name: normalized, cid: cid}, raw, meta)
        Cachex.put(@cache, {:name, normalized}, cid)
        {:ok, cid}

      {:error, :not_found} ->
        Cachex.put(@cache, {:name, normalized}, :not_found)
        {:error, :not_found}

      {:error, _reason} = err ->
        # Transient (network / rate-limited): do not cache; let the caller retry.
        err
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp seed(input) do
    ns = get(input, :namespace)
    id = get(input, :identifier)

    if is_binary(ns) and ns != "" and not is_nil(id) and to_string(id) != "" do
      {ns, to_string(id)}
    end
  end

  defp name(input), do: get(input, :name)

  defp get(input, key) do
    Map.get(input, key) || Map.get(input, to_string(key))
  end

  defp seed_identifier({_ns, id}), do: id
  defp seed_identifier(nil), do: nil

  # Always keep the requested name; append the top relevance-ordered PubChem
  # synonyms; dedupe.
  defp compound_synonyms(name, syns) do
    ([name] ++ (syns || []))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  # Structural descriptors only — the InChIKey is a global identifier and is
  # stored as a compound_identifiers row instead.
  defp structural_properties(props) do
    %{
      "iupac_name" => props.iupac_name,
      "molecular_formula" => props.molecular_formula,
      "smiles" => props.smiles,
      "isomeric_smiles" => props.isomeric_smiles,
      "inchi" => props.inchi
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new()
  end

  defp store_response(endpoint, fields, raw, meta) do
    Chemistry.store_raw_response(
      Map.merge(fields, %{
        endpoint: endpoint,
        raw_json: raw,
        etag: meta[:etag],
        api_version: meta[:api_version],
        retrieved_at: now()
      })
    )
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
