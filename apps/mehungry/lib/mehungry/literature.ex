defmodule Mehungry.Literature do
  @moduledoc """
  Literature context — scientific-literature discovery for the food domain.

  NCBI Entrez (PubMed) is treated as an external authority, exactly like USDA is
  for ingredients and PubChem is for compounds: `Mehungry.Literature.Entrez`
  crawls an ingredient's scientific name combined with compound/phytochemistry
  terms and records each discovered paper as a `ScientificStudy`, linked back to
  the ingredient (`StudyIngredient`) and — when the term matches the compound
  registry — the compound (`StudyCompound`).

  This context owns the registry, the join facts, and the two sidecar concerns:

    * `Entrez.RawResponse` (`entrez_responses`) — an append-only cache of every
      raw E-utilities payload, so the original response is never lost.
    * `CrawlAttempt` (`literature_crawl_attempts`) — a per-`(ingredient, term)`
      ledger that dedupes work and guarantees the batch crawl terminates.

  It represents **discovered literature only** — a study never asserts a dietary
  fact (that stays in `Mehungry.Food.Compounds` / `IngredientCompoundRelationship`).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Ingredient, IngredientScientificIdentity}

  alias Mehungry.Literature.{
    ScientificStudy,
    StudyIngredient,
    StudyCompound,
    StudyEntityMention,
    CrawlAttempt,
    AnnotationAttempt,
    Entrez,
    PubTator
  }

  alias Mehungry.Literature.Entrez.RawResponse
  alias Mehungry.Literature.PubTator.RawResponse, as: PubTatorRawResponse

  @doc """
  Crawl NCBI Entrez for one ingredient and sync discovered studies.

  See `Mehungry.Literature.Entrez.crawl_ingredient/2`.
  """
  defdelegate import_ingredient(ingredient_id, opts \\ []), to: Entrez, as: :crawl_ingredient

  @doc "The search terms (scientific name × compounds ∪ keywords) for an ingredient."
  defdelegate search_terms_for_ingredient(ingredient_id), to: Entrez

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

  @doc "Upsert a crawl attempt for a `(ingredient, search_term)` pair."
  def record_crawl_attempt(attrs) do
    %CrawlAttempt{}
    |> CrawlAttempt.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:ingredient_id, :search_term]
    )
  end

  @doc "Has `(ingredient, search_term)` already been crawled?"
  def crawl_attempted?(ingredient_id, search_term) do
    Repo.exists?(
      from(a in CrawlAttempt,
        where: a.ingredient_id == ^ingredient_id and a.search_term == ^search_term
      )
    )
  end

  @doc "The last time `(ingredient, search_term)` was crawled, or `nil` — the incremental watermark."
  def last_crawled_at(ingredient_id, search_term) do
    Repo.one(
      from(a in CrawlAttempt,
        where: a.ingredient_id == ^ingredient_id and a.search_term == ^search_term,
        select: a.last_crawled_at
      )
    )
  end

  # ── Batch selection + progress ────────────────────────────────────────────

  @doc "A batch of ingredients that have a scientific identity but no crawl attempt yet, newest first."
  def list_uncrawled_ingredients(limit) do
    Repo.all(
      from(i in Ingredient,
        left_join: a in CrawlAttempt,
        on: a.ingredient_id == i.id,
        where: i.id in subquery(identity_ingredient_ids()) and is_nil(a.id),
        order_by: [desc: i.id],
        limit: ^limit
      )
    )
  end

  @doc "Crawl coverage: how many identity-backed ingredients have been crawled, out of the total."
  def crawl_progress do
    total =
      from(i in Ingredient, where: i.id in subquery(identity_ingredient_ids()))
      |> Repo.aggregate(:count)

    processed =
      from(a in CrawlAttempt,
        where: a.ingredient_id in subquery(identity_ingredient_ids()),
        select: count(a.ingredient_id, :distinct)
      )
      |> Repo.one()

    %{processed: processed, total: total}
  end

  defp identity_ingredient_ids do
    from(sid in IngredientScientificIdentity, select: sid.ingredient_id)
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

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp to_int(_), do: nil
end
