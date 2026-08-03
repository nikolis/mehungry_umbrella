defmodule Mehungry.Literature.PubTator do
  @moduledoc """
  NCBI PubTator3 entity-extraction / annotation adapter.

  For a discovered `ScientificStudy`, it exports PubTator3's BioC JSON annotations
  and records the Chemical / Species / Disease mentions as `StudyEntityMention`
  facts. It behaves like the Entrez crawler does for discovery: it enriches the
  internal model and is never queried directly by the rest of the application —
  callers read `Mehungry.Literature`.

  Boundaries (the integration's hard requirements):

    * **Only extracted facts** — a mention captures the entity type, the identifier
      PubTator assigned, the preserved original text, its offset, and any
      confidence. Nothing is inferred.
    * **No relationship inference** — a mention is never promoted to an
      `IngredientCompoundRelationship`. For a chemical, `compound_id` is an
      *identity* link produced by `Mehungry.Chemistry.Resolver`, not a dietary fact.
    * **MeSH stays primary** — `normalized_identifier` is exactly what PubTator
      emitted (MeSH for chemicals/diseases, NCBI Taxonomy for species). A chemical's
      PubChem CID and other cross-references live on the resolved compound.
    * **History-preserving** — every raw PubTator payload is stored append-only.

  A transient failure (rate-limit / network) bubbles up as `{:error, reason}` so
  the batch worker can snooze/retry — no attempt is ledgered, keeping the retry
  idempotent.
  """

  require Logger

  alias Mehungry.Chemistry
  alias Mehungry.Literature
  alias Mehungry.Literature.PubTator.Client

  @cache :pubtator_cache

  @doc """
  Annotate one study with PubTator3 and sync the extracted entity mentions.

  Options:
    * `:refresh` — re-annotate even if the study was already attempted (bypasses
      the ledger + hot cache).

  Returns `{:ok, mentions_found}` — always advances, the attempt is ledgered — or
  `{:error, reason}` for a transient failure the batch worker should let Oban
  retry (no attempt ledgered).
  """
  @spec annotate_study(integer(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def annotate_study(study_id, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)

    case Literature.get_study(study_id) do
      %{pmid: pmid} = _study when is_integer(pmid) ->
        if not refresh and Literature.annotation_attempted?(study_id) do
          {:ok, 0}
        else
          annotate(study_id, pmid, refresh)
        end

      _ ->
        # No study / no PMID: nothing to annotate; do not ledger (FK-keyed).
        {:ok, 0}
    end
  end

  # ── annotation ─────────────────────────────────────────────────────────────

  defp annotate(study_id, pmid, refresh) do
    case fetch_data(pmid, refresh) do
      {:ok, %{mentions: [], relations: []}} ->
        record_attempt(study_id, "no_results", 0)
        {:ok, 0}

      {:ok, %{mentions: mentions, relations: relations}} ->
        persist(study_id, mentions, relations)

      {:error, {:rate_limited, _} = reason} ->
        {:error, reason}

      {:error, {:network, _} = reason} ->
        {:error, reason}

      {:error, :not_found} ->
        record_attempt(study_id, "no_results", 0)
        {:ok, 0}

      {:error, reason} ->
        Logger.warning("PubTator: annotate failed for pmid #{pmid} — #{inspect(reason)}")
        record_attempt(study_id, "error", 0)
        {:ok, 0}
    end
  end

  # Persist mentions first (a transient chemical-resolver failure bubbles up for a
  # retry); then the directional relations (DB-only resolution, best-effort); then
  # ledger the attempt once.
  defp persist(study_id, mentions, relations) do
    case persist_mentions(study_id, mentions) do
      {:ok, count} ->
        Literature.persist_study_relations(study_id, relations)
        record_attempt(study_id, "annotated", count)
        {:ok, count}

      {:error, _reason} = err ->
        err
    end
  end

  # Persist each mention. A transient resolver failure (rate-limit / network) on a
  # chemical bubbles up so the worker retries the whole study; every other resolver
  # outcome still records the mention (the extracted fact) with a nil compound_id.
  defp persist_mentions(study_id, mentions) do
    Enum.reduce_while(mentions, {:ok, 0}, fn mention, {:ok, count} ->
      case compound_id_for(mention) do
        {:ok, compound_id} ->
          store_mention(study_id, mention, compound_id)
          {:cont, {:ok, count + 1}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, _reason} = err ->
        err
    end
  end

  # Only chemicals are resolved to a compound identity. Species / diseases keep
  # their namespaced identifier and are stored without a compound link.
  defp compound_id_for(%{entity_type: "chemical"} = mention) do
    case Chemistry.resolve(resolver_input(mention), source: "pubtator") do
      {:ok, compound} ->
        {:ok, compound.id}

      {:error, {:rate_limited, _} = reason} ->
        {:error, reason}

      {:error, {:network, _} = reason} ->
        {:error, reason}

      {:error, _other} ->
        # Not found / definitive: still capture the mention, just unlinked.
        {:ok, nil}
    end
  end

  defp compound_id_for(_mention), do: {:ok, nil}

  # Prefer the normalized identifier (MeSH primary); fall back to the surface text
  # as the name-only anchor, per the resolver's fallback contract.
  defp resolver_input(%{normalized_identifier: id, text_span: text}) when is_binary(id) do
    case String.split(id, ":", parts: 2) do
      [namespace, identifier] -> %{namespace: namespace, identifier: identifier, name: text}
      _ -> %{name: text}
    end
  end

  defp resolver_input(%{text_span: text}), do: %{name: text}

  defp store_mention(study_id, mention, compound_id) do
    Literature.upsert_entity_mention(%{
      study_id: study_id,
      entity_type: mention.entity_type,
      normalized_identifier: mention.normalized_identifier,
      text_span: mention.text_span,
      offset: mention.offset,
      confidence: mention.confidence,
      source: "pubtator3",
      compound_id: compound_id
    })
  end

  # ── fetch (hot cache in front of the API) ────────────────────────────────────

  defp fetch_data(pmid, true), do: fetch_and_store(pmid)

  defp fetch_data(pmid, false) do
    case Cachex.get(@cache, {:pmid, pmid}) do
      {:ok, %{mentions: _} = data} -> {:ok, data}
      _ -> fetch_and_store(pmid)
    end
  end

  defp fetch_and_store(pmid) do
    case Client.annotate([pmid]) do
      {:ok, mentions, raw} ->
        Literature.store_pubtator_response(%{
          endpoint: "biocjson",
          pmid: pmid,
          raw_json: raw,
          retrieved_at: now()
        })

        data = %{mentions: mentions, relations: Client.parse_relations(raw)}
        Cachex.put(@cache, {:pmid, pmid}, data)
        {:ok, data}

      {:error, _reason} = err ->
        err
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp record_attempt(study_id, outcome, mentions_found) do
    Literature.record_annotation_attempt(%{
      study_id: study_id,
      outcome: outcome,
      mentions_found: mentions_found,
      last_annotated_at: now()
    })
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
