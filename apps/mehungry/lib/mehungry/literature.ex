defmodule Mehungry.Literature do
  @moduledoc """
  Literature context — scientific-literature discovery for the food domain.

  NCBI Entrez (PubMed) is treated as an external authority, exactly like USDA is
  for ingredients and PubChem is for compounds: `Mehungry.Literature.Entrez`
  crawls a food species' curated scientific name combined with
  compound/phytochemistry terms and records each discovered paper as a
  `ScientificStudy`, linked back to every ingredient curated onto the species
  (`StudyIngredient`) and — when the term matches the compound registry — the
  compound (`StudyCompound`).

  This context owns the registry, the join facts, and the two sidecar concerns:

    * `Entrez.RawResponse` (`entrez_responses`) — an append-only cache of every
      raw E-utilities payload, so the original response is never lost.
    * `CrawlAttempt` (`literature_crawl_attempts`) — a per-`(species, term)`
      ledger that dedupes work and guarantees the batch crawl terminates.

  It represents **discovered literature only** — a study never asserts a dietary
  fact (that stays in `Mehungry.Food.Compounds` / `IngredientCompoundRelationship`).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{FoundementalFood, FoundementalFoodSpecies}

  alias Mehungry.Literature.{
    ScientificStudy,
    StudyIngredient,
    StudyCompound,
    StudyEntityMention,
    StudyFullText,
    PmcFetchAttempt,
    CrawlAttempt,
    AnnotationAttempt,
    Entrez,
    PubTator
  }

  alias Mehungry.Literature.Entrez.RawResponse
  alias Mehungry.Literature.PubTator.RawResponse, as: PubTatorRawResponse

  @doc """
  Crawl NCBI Entrez for one food species and sync discovered studies.

  See `Mehungry.Literature.Entrez.crawl_species/2`.
  """
  defdelegate import_species(species_id, opts \\ []), to: Entrez, as: :crawl_species

  @doc "The search terms (scientific name × compounds ∪ keywords) for a species."
  defdelegate search_terms_for_species(species_id), to: Entrez

  @doc "Opens a tracked run and enqueues the first crawl batch."
  def enqueue_crawl do
    run = Mehungry.Literature.CrawlRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.LiteratureCrawlWorker.new()
      |> Oban.insert()

    {:ok, run}
  end

  @doc """
  Annotate one study with PubTator3 and sync its entity mentions.

  See `Mehungry.Literature.PubTator.annotate_study/2`.
  """
  defdelegate annotate_study(study_id, opts \\ []), to: PubTator

  @doc "Opens a tracked annotation run and enqueues the first annotation batch."
  def enqueue_annotation do
    run = Mehungry.Literature.AnnotationRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.PubTatorAnnotationWorker.new()
      |> Oban.insert()

    {:ok, run}
  end

  # ── Study registry (deduped by PMID) ──────────────────────────────────────

  @doc "Find-or-refresh a study by its natural key `pmid`; enrichment is additive-safe upsert."
  def upsert_study(attrs) do
    %ScientificStudy{}
    |> ScientificStudy.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:pmid],
      returning: true
    )
  end

  def get_study(id), do: Repo.get(ScientificStudy, id)

  def get_study_by_pmid(pmid), do: Repo.get_by(ScientificStudy, pmid: pmid)

  def list_studies, do: Repo.all(from(s in ScientificStudy, order_by: [desc: s.id]))

  # ── Study ↔ ingredient / compound links (idempotent) ──────────────────────

  def link_study_ingredient(attrs) do
    %StudyIngredient{}
    |> StudyIngredient.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:study_id, :ingredient_id, :search_term]
    )
  end

  def link_study_compound(attrs) do
    %StudyCompound{}
    |> StudyCompound.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:study_id, :compound_id])
  end

  # ── Raw response cache (append-only) ──────────────────────────────────────

  @doc "Persist a raw Entrez payload. Append-only — never overwritten."
  def store_raw_response(attrs) do
    %RawResponse{}
    |> RawResponse.changeset(attrs)
    |> Repo.insert()
  end

  @doc "The most recent stored PMID list for an `esearch` query, or `nil`."
  def latest_search_pmids(query) do
    case Repo.one(
           from(r in RawResponse,
             where: r.endpoint == "esearch" and r.query == ^query,
             order_by: [desc: r.id],
             limit: 1,
             select: r.raw_json
           )
         ) do
      %{"esearchresult" => %{"idlist" => ids}} when is_list(ids) ->
        ids |> Enum.map(&to_int/1) |> Enum.reject(&is_nil/1)

      _ ->
        nil
    end
  end

  # ── Crawl ledger (dedup + incremental watermark) ──────────────────────────

  @doc "Upsert a crawl attempt for a `(species, search_term)` pair."
  def record_crawl_attempt(attrs) do
    %CrawlAttempt{}
    |> CrawlAttempt.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:foundemental_species_id, :search_term]
    )
  end

  @doc "Has `(species, search_term)` already been crawled?"
  def crawl_attempted?(species_id, search_term) do
    Repo.exists?(
      from(a in CrawlAttempt,
        where: a.foundemental_species_id == ^species_id and a.search_term == ^search_term
      )
    )
  end

  @doc "The last time `(species, search_term)` was crawled, or `nil` — the incremental watermark."
  def last_crawled_at(species_id, search_term) do
    Repo.one(
      from(a in CrawlAttempt,
        where: a.foundemental_species_id == ^species_id and a.search_term == ^search_term,
        select: a.last_crawled_at
      )
    )
  end

  # ── Batch selection + progress ────────────────────────────────────────────

  @doc "A batch of food species that have a scientific name but no crawl attempt yet, newest first."
  def list_uncrawled_species(limit) do
    Repo.all(
      from(s in FoundementalFoodSpecies,
        left_join: a in CrawlAttempt,
        on: a.foundemental_species_id == s.id,
        where: not is_nil(s.scientific_name) and s.scientific_name != "" and is_nil(a.id),
        order_by: [desc: s.id],
        limit: ^limit
      )
    )
  end

  @doc "Crawl coverage: how many named food species have been crawled, out of the total."
  def crawl_progress do
    total =
      from(s in FoundementalFoodSpecies,
        where: not is_nil(s.scientific_name) and s.scientific_name != ""
      )
      |> Repo.aggregate(:count)

    processed =
      from(a in CrawlAttempt,
        join: s in FoundementalFoodSpecies,
        on: s.id == a.foundemental_species_id,
        where: not is_nil(s.scientific_name) and s.scientific_name != "",
        select: count(a.foundemental_species_id, :distinct)
      )
      |> Repo.one()

    %{processed: processed, total: total}
  end

  # ── Read API (for future UIs) ─────────────────────────────────────────────

  @doc "All studies discovered for an ingredient, newest first (each with its link preloaded)."
  def list_studies_for_ingredient(ingredient_id) do
    Repo.all(
      from(l in StudyIngredient,
        join: s in ScientificStudy,
        on: s.id == l.study_id,
        where: l.ingredient_id == ^ingredient_id,
        order_by: [desc: s.id],
        preload: [study: s]
      )
    )
    |> Enum.map(& &1.study)
    |> Enum.uniq_by(& &1.id)
  end

  @doc "All studies linked to a compound."
  def list_studies_for_compound(compound_id) do
    Repo.all(
      from(l in StudyCompound,
        join: s in ScientificStudy,
        on: s.id == l.study_id,
        where: l.compound_id == ^compound_id,
        order_by: [desc: s.id],
        preload: [study: s]
      )
    )
    |> Enum.map(& &1.study)
    |> Enum.uniq_by(& &1.id)
  end

  @doc "All ingredients a study was discovered for."
  def list_ingredients_for_study(study_id) do
    Repo.all(
      from(l in StudyIngredient,
        where: l.study_id == ^study_id,
        preload: [:ingredient]
      )
    )
    |> Enum.map(& &1.ingredient)
    |> Enum.uniq_by(& &1.id)
  end

  # ── PubTator3 entity mentions (extracted facts) ───────────────────────────

  @doc "Insert-or-update an extracted entity mention on its natural key."
  def upsert_entity_mention(attrs) do
    %StudyEntityMention{}
    |> StudyEntityMention.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:study_id, :entity_type, :normalized_identifier, :offset]
    )
  end

  @doc "Persist a raw PubTator payload. Append-only — never overwritten."
  def store_pubtator_response(attrs) do
    %PubTatorRawResponse{}
    |> PubTatorRawResponse.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Upsert the annotation ledger row for a study."
  def record_annotation_attempt(attrs) do
    %AnnotationAttempt{}
    |> AnnotationAttempt.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:study_id]
    )
  end

  @doc "Has `study_id` already been annotated?"
  def annotation_attempted?(study_id) do
    Repo.exists?(from(a in AnnotationAttempt, where: a.study_id == ^study_id))
  end

  @doc "A batch of studies with no annotation attempt yet, newest first."
  def list_unannotated_studies(limit) do
    Repo.all(
      from(s in ScientificStudy,
        left_join: a in AnnotationAttempt,
        on: a.study_id == s.id,
        where: is_nil(a.id),
        order_by: [desc: s.id],
        limit: ^limit
      )
    )
  end

  @doc "Annotation coverage: how many studies have been annotated, out of the total."
  def annotation_progress do
    total = Repo.aggregate(ScientificStudy, :count)
    processed = Repo.aggregate(AnnotationAttempt, :count, :study_id)
    %{processed: processed, total: total}
  end

  @doc "All entity mentions extracted from a study, ordered by offset."
  def list_entity_mentions_for_study(study_id) do
    Repo.all(
      from(m in StudyEntityMention,
        where: m.study_id == ^study_id,
        order_by: [asc: m.offset, asc: m.id]
      )
    )
  end

  @doc "A study's entity mentions of one type (`\"chemical\"|\"species\"|\"disease\"`)."
  def list_mentions_by_type(study_id, entity_type) do
    Repo.all(
      from(m in StudyEntityMention,
        where: m.study_id == ^study_id and m.entity_type == ^entity_type,
        order_by: [asc: m.offset, asc: m.id]
      )
    )
  end

  @doc "All studies that mention a resolved compound (via chemical mentions)."
  def list_studies_for_compound_mention(compound_id) do
    Repo.all(
      from(m in StudyEntityMention,
        join: s in ScientificStudy,
        on: s.id == m.study_id,
        where: m.compound_id == ^compound_id,
        order_by: [desc: s.id],
        preload: [study: s]
      )
    )
    |> Enum.map(& &1.study)
    |> Enum.uniq_by(& &1.id)
  end

  # ── Review reads (admin UI) ────────────────────────────────────────────────

  @doc "Total number of discovered studies."
  def count_studies, do: Repo.aggregate(ScientificStudy, :count)

  @doc "A page of studies, newest first, with an optional title/PMID search."
  def list_studies_page(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    ScientificStudy
    |> studies_search(normalize_search(Keyword.get(opts, :search)))
    |> order_by(desc: :id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Count of studies matching the same optional search as `list_studies_page/1`."
  def count_studies_matching(search) do
    ScientificStudy
    |> studies_search(normalize_search(search))
    |> Repo.aggregate(:count)
  end

  defp normalize_search(term) when is_binary(term) do
    case String.trim(term) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_search(_), do: nil

  defp studies_search(query, nil), do: query

  defp studies_search(query, term) do
    like = "%#{term}%"

    case Integer.parse(term) do
      {pmid, ""} -> from(s in query, where: ilike(s.title, ^like) or s.pmid == ^pmid)
      _ -> from(s in query, where: ilike(s.title, ^like))
    end
  end

  @doc "Map of `study_id => linked-ingredient count` for the given study ids."
  def study_ingredient_counts(study_ids) do
    from(l in StudyIngredient,
      where: l.study_id in ^study_ids,
      group_by: l.study_id,
      select: {l.study_id, count(l.ingredient_id, :distinct)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Map of `study_id => entity-mention count` for the given study ids."
  def study_mention_counts(study_ids) do
    from(m in StudyEntityMention,
      where: m.study_id in ^study_ids,
      group_by: m.study_id,
      select: {m.study_id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Crawl-ledger outcome summary: counts per outcome + total studies found."
  def crawl_ledger_summary do
    rows =
      from(a in CrawlAttempt,
        group_by: a.outcome,
        select: {a.outcome, count(a.id), sum(a.studies_found)}
      )
      |> Repo.all()

    base = %{"matched" => 0, "no_results" => 0, "error" => 0}

    counts = Enum.reduce(rows, base, fn {outcome, c, _}, acc -> Map.put(acc, outcome, c) end)
    studies_found = Enum.reduce(rows, 0, fn {_, _, s}, acc -> acc + (s || 0) end)

    Map.put(counts, :studies_found, studies_found)
  end

  @doc """
  Annotation-ledger summary: how many studies were processed, the outcome breakdown
  (`annotated | no_results | error`), and the total mentions found. Lets the review
  UI show that annotation *ran* even when it extracted nothing (e.g. papers too
  recent for PubTator3).
  """
  def annotation_ledger_summary do
    rows =
      from(a in AnnotationAttempt,
        group_by: a.outcome,
        select: {a.outcome, count(a.id), sum(a.mentions_found)}
      )
      |> Repo.all()

    base = %{"annotated" => 0, "no_results" => 0, "error" => 0}
    counts = Enum.reduce(rows, base, fn {outcome, c, _}, acc -> Map.put(acc, outcome, c) end)
    mentions = Enum.reduce(rows, 0, fn {_, _, m}, acc -> acc + (m || 0) end)
    processed = Enum.reduce(rows, 0, fn {_, c, _}, acc -> acc + c end)

    counts |> Map.put(:mentions_found, mentions) |> Map.put(:processed, processed)
  end

  @doc "Totals of entity mentions by type (`chemical | species | disease`)."
  def mention_type_totals do
    from(m in StudyEntityMention, group_by: m.entity_type, select: {m.entity_type, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Number of studies that have at least one entity mention."
  def count_annotated_studies do
    Repo.one(from(m in StudyEntityMention, select: count(m.study_id, :distinct))) || 0
  end

  @doc "A page of studies that have entity mentions, newest first."
  def list_annotated_studies_page(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    annotated = from(m in StudyEntityMention, select: m.study_id)

    from(s in ScientificStudy,
      where: s.id in subquery(annotated),
      order_by: [desc: s.id],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc "Map of `study_id => %{entity_type => count}` for the given study ids."
  def study_mention_type_counts(study_ids) do
    from(m in StudyEntityMention,
      where: m.study_id in ^study_ids,
      group_by: [m.study_id, m.entity_type],
      select: {m.study_id, m.entity_type, count(m.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {sid, type, count}, acc ->
      Map.update(acc, sid, %{type => count}, &Map.put(&1, type, count))
    end)
  end

  @doc """
  Distinct-study co-occurrence counts per `(ingredient_id, compound_id)`: a
  resolved chemical mention appearing in a paper that is also linked to the
  ingredient. Returns `[%{ingredient_id: _, compound_id: _, study_count: _}]` —
  the literature evidence for a candidate ingredient↔compound relationship. This
  is discovery evidence, never a dietary assertion.
  """
  def compound_ingredient_cooccurrences do
    Repo.all(
      from(m in StudyEntityMention,
        join: si in StudyIngredient,
        on: si.study_id == m.study_id,
        where: m.entity_type == "chemical" and not is_nil(m.compound_id),
        group_by: [si.ingredient_id, m.compound_id],
        select: %{
          ingredient_id: si.ingredient_id,
          compound_id: m.compound_id,
          study_count: count(m.study_id, :distinct)
        }
      )
    )
  end

  @doc "Distinct co-occurrence study count for one `(ingredient_id, compound_id)` pair."
  def cooccurrence_study_count(ingredient_id, compound_id) do
    Repo.one(
      from(m in StudyEntityMention,
        join: si in StudyIngredient,
        on: si.study_id == m.study_id,
        where:
          m.entity_type == "chemical" and m.compound_id == ^compound_id and
            si.ingredient_id == ^ingredient_id,
        select: count(m.study_id, :distinct)
      )
    ) || 0
  end

  # ── Species-level co-occurrence (candidate derivation, stage 4) ─────────────
  # Same evidence as the ingredient version, one join deeper: a study's linked
  # ingredients are grouped up to their `FoundementalFoodSpecies` via `FoundementalFood`.

  @doc """
  Distinct-study co-occurrence counts per `(species_id, compound_id)`: a resolved
  chemical mention appearing in a paper linked to any ingredient of the species.
  Returns `[%{species_id: _, compound_id: _, study_count: _}]`.
  """
  def species_compound_cooccurrences do
    Repo.all(
      from(m in StudyEntityMention,
        join: si in StudyIngredient,
        on: si.study_id == m.study_id,
        join: ff in FoundementalFood,
        on: ff.ingredient_id == si.ingredient_id,
        where: m.entity_type == "chemical" and not is_nil(m.compound_id),
        group_by: [ff.foundemental_species_id, m.compound_id],
        select: %{
          species_id: ff.foundemental_species_id,
          compound_id: m.compound_id,
          study_count: count(m.study_id, :distinct)
        }
      )
    )
  end

  @doc "Distinct co-occurrence study count for one `(species_id, compound_id)` pair."
  def species_cooccurrence_study_count(species_id, compound_id) do
    Repo.one(
      from(m in StudyEntityMention,
        join: si in StudyIngredient,
        on: si.study_id == m.study_id,
        join: ff in FoundementalFood,
        on: ff.ingredient_id == si.ingredient_id,
        where:
          m.entity_type == "chemical" and m.compound_id == ^compound_id and
            ff.foundemental_species_id == ^species_id,
        select: count(m.study_id, :distinct)
      )
    ) || 0
  end

  @doc "Distinct study ids backing a `(species_id, compound_id)` co-occurrence — the provenance."
  def species_cooccurrence_studies(species_id, compound_id) do
    Repo.all(
      from(m in StudyEntityMention,
        join: si in StudyIngredient,
        on: si.study_id == m.study_id,
        join: ff in FoundementalFood,
        on: ff.ingredient_id == si.ingredient_id,
        where:
          m.entity_type == "chemical" and m.compound_id == ^compound_id and
            ff.foundemental_species_id == ^species_id,
        distinct: true,
        select: m.study_id
      )
    )
  end

  # ── PMC full-text (measurement extraction pipeline) ────────────────────────

  @doc "Store (or refresh) a study's fetched PMC full text; one row per study."
  def upsert_full_text(attrs) do
    %StudyFullText{}
    |> StudyFullText.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:study_id]
    )
  end

  @doc "Upsert the PMC fetch-attempt ledger row for a study."
  def record_pmc_attempt(attrs) do
    %PmcFetchAttempt{}
    |> PmcFetchAttempt.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:study_id]
    )
  end

  @doc "Has a PMC fetch been attempted for this study?"
  def pmc_attempted?(study_id),
    do: Repo.exists?(from(a in PmcFetchAttempt, where: a.study_id == ^study_id))

  @doc "A study's stored PMC full text, or `nil`."
  def get_full_text(study_id), do: Repo.get_by(StudyFullText, study_id: study_id)

  @doc "A batch of PMID-bearing studies with no PMC fetch attempt yet, newest first."
  def list_unfetched_studies(limit) do
    Repo.all(
      from(s in ScientificStudy,
        left_join: a in PmcFetchAttempt,
        on: a.study_id == s.id,
        where: not is_nil(s.pmid) and is_nil(a.id),
        order_by: [desc: s.id],
        limit: ^limit
      )
    )
  end

  @doc "PMC fetch coverage: attempted studies / PMID-bearing studies."
  def pmc_fetch_progress do
    total = Repo.aggregate(from(s in ScientificStudy, where: not is_nil(s.pmid)), :count)
    processed = Repo.aggregate(PmcFetchAttempt, :count, :study_id)
    %{processed: processed, total: total}
  end

  @doc "Distinct `FoundementalFoodSpecies` ids a study is linked to (via its ingredients)."
  def species_ids_for_study(study_id) do
    Repo.all(
      from(l in StudyIngredient,
        join: ff in FoundementalFood,
        on: ff.ingredient_id == l.ingredient_id,
        where: l.study_id == ^study_id,
        distinct: true,
        select: ff.foundemental_species_id
      )
    )
  end

  @doc "Distinct resolved compound ids a study mentions (chemicals)."
  def compound_ids_for_study(study_id) do
    Repo.all(
      from(m in StudyEntityMention,
        where:
          m.study_id == ^study_id and m.entity_type == "chemical" and not is_nil(m.compound_id),
        distinct: true,
        select: m.compound_id
      )
    )
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp to_int(_), do: nil
end
