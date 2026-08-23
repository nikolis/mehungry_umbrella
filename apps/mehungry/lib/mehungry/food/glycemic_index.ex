defmodule Mehungry.Food.GlycemicIndex do
  @moduledoc """
  **Path-B Glycemic Index pipeline** — GI values *re-derived from primary literature*,
  not ingested from the copyrighted International Tables (see
  `docs/science/glycemic_index_licensing.md`).

  Structurally the compound-measurement pipeline applied to GI:

    1. **Discover** — the Entrez crawl finds GI feeding-trial studies (species ×
       `"glycemic index"` keyword), linking each `ScientificStudy` to the species.
    2. **Extract** — the non-deployed local-AI service reads a paper's PMC full text and
       extracts the measured GI value(s); `record_extracted_gi/2` fans each finding over
       every `FoundementalFoodSpecies` the study links to as a `GlycemicIndexCandidate`.
    3. **Review** — an admin promotes/rejects at `/professional/glycemic-index`. Nothing
       auto-promotes: a study can test several foods, so a wrong fan-out would write a
       wrong health number. Promotion fans the value onto every ingredient of the
       species as a reviewed `IngredientScientificProperty(property_key:
       "glycemic_index", basis: "glucose=100")`, recording the ids so an Undo removes
       exactly those.

  Public functions are exposed on the `Mehungry.Food` facade under distinct
  `*_glycemic_*` names so they don't collide with the compound pipeline.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.Enrichment
  alias Mehungry.Food.FoundementalFoods
  alias Mehungry.Food.GlycemicIndexCandidate, as: Candidate
  alias Mehungry.Food.IngredientScientificProperty
  alias Mehungry.Literature.ScientificStudy

  # ── Extraction intake (local-AI fan-out) ─────────────────────────────────────

  @doc """
  Record the GI value(s) extracted from a study, fanning each finding over every
  `FoundementalFoodSpecies` the study links to. `findings` is a list of maps like
  `%{gi_value: 54.0, gi_sem: 3.0, iso_method: true, sample_size: 10, country: "Italy",
  year: 2019, reference_food: "glucose", analytical_method: "...", score: 0.9,
  raw_span: "...", extraction_method: "automated"}`. Returns the number of candidates
  upserted. Idempotent on `(study_id, species_id, gi_value)`.
  """
  def record_extracted_gi(study_id, findings, species_ids)
      when is_integer(study_id) and is_list(findings) and is_list(species_ids) do
    source = study_enrichment_source(study_id)

    for finding <- findings, species_id <- species_ids, reduce: 0 do
      count ->
        {:ok, _} =
          finding
          |> Map.merge(%{
            study_id: study_id,
            foundemental_species_id: species_id,
            enrichment_source_id: source && source.id,
            status: "pending"
          })
          |> upsert_candidate()

        count + 1
    end
  end

  @doc "Upsert one candidate, refreshing only extraction fields (never review state)."
  def upsert_candidate(attrs) do
    %Candidate{}
    |> Candidate.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :gi_sem,
           :reference_food,
           :sample_size,
           :country,
           :year,
           :analytical_method,
           :iso_method,
           :score,
           :raw_span,
           :extraction_method,
           :enrichment_source_id,
           :updated_at
         ]},
      conflict_target: [:study_id, :foundemental_species_id, :gi_value],
      returning: true
    )
  end

  # Cite each promoted value by the primary study: its DOI when present, else a
  # canonical PubMed URL. `source_type` is constrained to doi|url|dataset|book.
  defp study_enrichment_source(study_id) do
    case Repo.get(ScientificStudy, study_id) do
      nil ->
        nil

      study ->
        {type, identifier, url} = study_citation(study)

        {:ok, source} =
          Enrichment.upsert_enrichment_source(%{
            source_type: type,
            identifier: identifier,
            title: study.title,
            url: url,
            retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        source
    end
  end

  defp study_citation(%ScientificStudy{doi: doi}) when is_binary(doi) and doi != "",
    do: {"doi", doi, "https://doi.org/#{doi}"}

  defp study_citation(%ScientificStudy{pmid: pmid}) when is_integer(pmid) do
    url = "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"
    {"url", url, url}
  end

  # ── Promotion / review ───────────────────────────────────────────────────────

  @doc """
  Promote a candidate: write its GI value onto every ingredient of the matched species
  (or the fallback ingredient) as a reviewed `IngredientScientificProperty`, and flip
  the candidate to `promoted`. Accepts a struct or id. Returns `{:ok, candidate}` or
  `{:error, :no_ingredients}`.
  """
  def promote_candidate(%Candidate{} = candidate), do: do_promote(candidate)
  def promote_candidate(id) when is_integer(id), do: promote_candidate(get_candidate!(id))

  @doc "Override the matched species (manual match) then promote in one step."
  def promote_candidate(id, species_id) when is_integer(id) and is_integer(species_id) do
    id
    |> get_candidate!()
    |> Candidate.changeset(%{foundemental_species_id: species_id, extraction_method: "manual"})
    |> Repo.update!()
    |> promote_candidate()
  end

  defp do_promote(%Candidate{} = candidate) do
    case target_ingredient_ids(candidate) do
      [] ->
        {:error, :no_ingredients}

      ingredient_ids ->
        property_ids = Enum.map(ingredient_ids, &write_property(&1, candidate))

        candidate
        |> Candidate.changeset(%{status: "promoted", promoted_property_ids: property_ids})
        |> Repo.update()
    end
  end

  defp write_property(ingredient_id, %Candidate{} = candidate) do
    {:ok, property} =
      Enrichment.upsert_scientific_property(%{
        ingredient_id: ingredient_id,
        property_key: "glycemic_index",
        value: candidate.gi_value,
        unit: "GI",
        basis: "glucose=100",
        source: "external_db",
        confidence: candidate.score,
        reviewed: true,
        retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second),
        enrichment_source_id: candidate.enrichment_source_id
      })

    property.id
  end

  defp target_ingredient_ids(%Candidate{foundemental_species_id: species_id})
       when is_integer(species_id) do
    FoundementalFoods.list_ingredient_ids_for_species(species_id)
  end

  defp target_ingredient_ids(%Candidate{ingredient_id: ingredient_id})
       when is_integer(ingredient_id),
       do: [ingredient_id]

  defp target_ingredient_ids(_), do: []

  @doc "Mark a candidate `rejected` (leaves the review queue, writes no fact)."
  def reject_candidate(%Candidate{} = candidate),
    do: candidate |> Candidate.changeset(%{status: "rejected"}) |> Repo.update()

  def reject_candidate(id) when is_integer(id), do: reject_candidate(get_candidate!(id))

  @doc """
  Undo a promoted candidate: delete exactly the `IngredientScientificProperty` rows it
  wrote (`promoted_property_ids`) and mark it `rejected` so a re-extraction won't
  re-promote it.
  """
  def unpromote_candidate(%Candidate{} = candidate) do
    delete_properties(candidate.promoted_property_ids)

    candidate
    |> Candidate.changeset(%{status: "rejected", promoted_property_ids: []})
    |> Repo.update()
  end

  def unpromote_candidate(id) when is_integer(id), do: unpromote_candidate(get_candidate!(id))

  defp delete_properties(nil), do: :ok

  defp delete_properties(ids) do
    Repo.delete_all(from(p in IngredientScientificProperty, where: p.id in ^ids))
    :ok
  end

  # ── Queries ──────────────────────────────────────────────────────────────────

  @doc "Pending candidates for review, ISO-method + strongest extraction first; paged."
  def list_pending_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(c in Candidate,
        where: c.status == "pending",
        order_by: [desc: c.iso_method, desc: c.score, asc: c.id],
        preload: [:study, :species],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  @doc "Promoted candidates (curated facts), newest first; paged."
  def list_promoted_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(c in Candidate,
        where: c.status == "promoted",
        order_by: [desc: c.updated_at, desc: c.id],
        preload: [:study, :species],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  def get_candidate!(id), do: Repo.get!(Candidate, id) |> Repo.preload([:study, :species])

  def count_pending_candidates, do: count_by_status("pending")
  def count_promoted_candidates, do: count_by_status("promoted")

  defp count_by_status(status),
    do: Repo.aggregate(from(c in Candidate, where: c.status == ^status), :count, :id)

  @doc """
  Our re-derived GI values grouped by species, for the verification harness
  (`OracleDiff`). Returns `[%{name: species_name, values: [gi_value, ...]}]`. `:statuses`
  selects which candidate states to include (default `["pending", "promoted"]` — i.e.
  everything not rejected).
  """
  def rederived_by_species(opts \\ []) do
    statuses = Keyword.get(opts, :statuses, ["pending", "promoted"])

    Repo.all(
      from(c in Candidate,
        join: s in assoc(c, :species),
        where: c.status in ^statuses and not is_nil(c.foundemental_species_id),
        select: {s.name, c.gi_value}
      )
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {name, values} -> %{name: name, values: values} end)
  end
end
