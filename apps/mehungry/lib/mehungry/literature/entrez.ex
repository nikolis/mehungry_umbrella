defmodule Mehungry.Literature.Entrez do
  @moduledoc """
  NCBI Entrez (PubMed) crawler / discovery adapter.

  For a food species with a curated scientific name
  (`Mehungry.Food.FoundementalFoodSpecies.scientific_name`), it builds a set of
  search terms — the binomial name combined with each compound already linked to
  the species plus a fixed phytochemistry keyword set — runs them through the
  E-utilities `esearch`/`efetch` client, and **syncs discovered papers into
  `Mehungry.Literature`**. Each discovered study is linked (`StudyIngredient`) to
  every USDA ingredient curated onto the species, so downstream candidate
  derivation stays ingredient-keyed. It behaves like the PubChem importer does for
  compounds: it enriches the internal model and is never queried directly by the
  rest of the application — callers read `Mehungry.Literature`.

  Guarantees:

    * **Deduplicated** — studies converge on a single `scientific_studies` row per
      PMID; links are idempotent; already-crawled `(species, term)` pairs are
      skipped (no HTTP) unless `:refresh` is passed.
    * **Incremental** — a `:refresh` crawl restricts `esearch` to papers newer than
      the term's last crawl (`mindate`), so re-crawls fetch only new evidence.
    * **History-preserving** — every raw E-utilities payload is stored append-only
      in `entrez_responses`.

  A transient failure (rate-limit / network) bubbles up as `{:error, reason}` so
  the batch worker can snooze/retry — no attempt is ledgered, keeping the retry
  idempotent. A definitive per-term failure is ledgered as `"error"` and the crawl
  advances so one bad term can't stall the run.
  """

  require Logger

  alias Mehungry.Food
  alias Mehungry.Literature
  alias Mehungry.Literature.Entrez.Client

  @cache :entrez_cache

  # Generic phytochemistry terms applied to every species (in addition to the
  # compounds already linked to it). A term matching a registry compound by name
  # also drives a StudyCompound link.
  @generic_keywords ~w(phytochemical polyphenol flavonoid antioxidant bioactive)

  @doc """
  Crawl Entrez for one food species and sync discovered studies.

  Options:
    * `:refresh` — re-crawl every term (bypasses the ledger + caches) and restrict
      each search to papers newer than that term's last crawl.

  Returns `{:ok, studies_found}` — always advances, attempts are ledgered — or
  `{:error, reason}` for a transient failure the batch worker should let Oban
  retry (no attempt ledgered).
  """
  @spec crawl_species(integer(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def crawl_species(species_id, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, false)

    case search_terms_for_species(species_id) do
      [] ->
        # Defensive: a crawlable species always has a name, but never leave one
        # unledgered or the batch worker can't terminate.
        record_attempt(species_id, "(no scientific name)", "no_results", 0)
        {:ok, 0}

      terms ->
        # Fetch the species' curated ingredients once — every discovered study is
        # linked to each of them.
        ingredient_ids = Food.list_ingredient_ids_for_species(species_id)

        Enum.reduce_while(terms, {:ok, 0}, fn term, {:ok, acc} ->
          cond do
            not refresh and Literature.crawl_attempted?(species_id, term.term) ->
              {:cont, {:ok, acc}}

            true ->
              case crawl_term(species_id, ingredient_ids, term, refresh) do
                {:ok, n} -> {:cont, {:ok, acc + n}}
                {:error, reason} -> {:halt, {:error, reason}}
              end
          end
        end)
    end
  end

  @doc """
  The search terms for a food species: `scientific_name × (linked compounds ∪
  generic keywords)`. Each term carries the `compound_id` it should link to
  (nil for a generic term that matches no registry compound). Returns `[]` when
  the species has no scientific name.
  """
  def search_terms_for_species(species_id) do
    case scientific_name(species_id) do
      nil ->
        []

      sci_name ->
        compound_terms =
          for compound <- Food.list_positive_compounds_for_species(species_id) do
            %{
              term: "#{sci_name} #{compound.name}",
              compound_id: compound.id,
              scientific_name: sci_name
            }
          end

        generic_terms =
          for keyword <- @generic_keywords do
            compound = Food.get_compound_by_name(keyword)

            %{
              term: "#{sci_name} #{keyword}",
              compound_id: compound && compound.id,
              scientific_name: sci_name
            }
          end

        (compound_terms ++ generic_terms)
        |> Enum.uniq_by(& &1.term)
    end
  end

  # ── per-term crawl ─────────────────────────────────────────────────────────

  defp crawl_term(species_id, ingredient_ids, %{term: term} = spec, refresh) do
    search_opts = if refresh, do: mindate_opts(species_id, term), else: []

    case search(term, refresh, search_opts) do
      {:ok, []} ->
        record_attempt(species_id, term, "no_results", 0)
        {:ok, 0}

      {:ok, pmids} ->
        fetch_and_link(species_id, ingredient_ids, spec, pmids)

      {:error, {:rate_limited, _} = reason} ->
        {:error, reason}

      {:error, {:network, _} = reason} ->
        {:error, reason}

      {:error, :not_found} ->
        record_attempt(species_id, term, "no_results", 0)
        {:ok, 0}

      {:error, reason} ->
        Logger.warning("Entrez: esearch failed for #{inspect(term)} — #{inspect(reason)}")
        record_attempt(species_id, term, "error", 0)
        {:ok, 0}
    end
  end

  defp fetch_and_link(species_id, ingredient_ids, %{term: term} = spec, pmids) do
    case fetch_studies(pmids) do
      {:ok, studies} ->
        Enum.each(studies, &link_study(ingredient_ids, spec, &1))
        record_attempt(species_id, term, "matched", length(studies))
        {:ok, length(studies)}

      {:error, {:rate_limited, _} = reason} ->
        {:error, reason}

      {:error, {:network, _} = reason} ->
        {:error, reason}

      {:error, reason} ->
        Logger.warning("Entrez: efetch failed for #{inspect(term)} — #{inspect(reason)}")
        record_attempt(species_id, term, "error", 0)
        {:ok, 0}
    end
  end

  defp link_study(
         ingredient_ids,
         %{term: term, compound_id: compound_id, scientific_name: sci_name},
         attrs
       ) do
    {:ok, study} = Literature.upsert_study(Map.put(attrs, :retrieved_at, now()))

    # Fan the discovered paper out to every ingredient curated onto the species.
    for ingredient_id <- ingredient_ids do
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: ingredient_id,
        search_term: term,
        scientific_name: sci_name,
        source: "pubmed"
      })
    end

    if compound_id do
      Literature.link_study_compound(%{
        study_id: study.id,
        compound_id: compound_id,
        search_term: term
      })
    end

    study
  end

  # ── esearch (two-layer cache) + efetch ─────────────────────────────────────

  # A refresh bypasses both caches so re-crawls see fresh (date-windowed) results.
  defp search(term, true, opts), do: fetch_search(term, opts)

  defp search(term, false, opts) do
    case Cachex.get(@cache, {:search, term}) do
      {:ok, pmids} when is_list(pmids) ->
        {:ok, pmids}

      _ ->
        case Literature.latest_search_pmids(term) do
          pmids when is_list(pmids) ->
            Cachex.put(@cache, {:search, term}, pmids)
            {:ok, pmids}

          nil ->
            fetch_search(term, opts)
        end
    end
  end

  defp fetch_search(term, opts) do
    case Client.esearch(term, opts) do
      {:ok, pmids, _count, raw} ->
        Literature.store_raw_response(%{
          endpoint: "esearch",
          query: term,
          raw_json: raw,
          retrieved_at: now()
        })

        Cachex.put(@cache, {:search, term}, pmids)
        {:ok, pmids}

      {:error, _reason} = err ->
        err
    end
  end

  defp fetch_studies(pmids) do
    case Client.efetch(pmids) do
      {:ok, studies, raw} ->
        Literature.store_raw_response(%{
          endpoint: "efetch",
          query: nil,
          raw_json: raw,
          retrieved_at: now()
        })

        {:ok, studies}

      {:error, _reason} = err ->
        err
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp scientific_name(species_id) do
    case Food.get_foundemental_species!(species_id) do
      %{scientific_name: name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp mindate_opts(species_id, term) do
    case Literature.last_crawled_at(species_id, term) do
      %DateTime{} = dt -> [mindate: Calendar.strftime(dt, "%Y/%m/%d")]
      _ -> []
    end
  end

  defp record_attempt(species_id, term, outcome, studies_found) do
    Literature.record_crawl_attempt(%{
      foundemental_species_id: species_id,
      search_term: term,
      outcome: outcome,
      studies_found: studies_found,
      last_crawled_at: now()
    })
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
