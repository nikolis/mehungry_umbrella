defmodule Mehungry.Science.PipelineReset do
  @moduledoc """
  Ops reset helpers for the scientific pipeline — one per run-stage on
  `/professional/science`. Each clears only that stage's generated artifacts (and,
  for the crawl, everything downstream that hangs off discovered studies), in
  FK-safe child→parent order inside a transaction, and returns a
  `%{table => rows_deleted}` map.

  Curated inputs are always preserved: `FoundementalFoodSpecies`, the compound
  registry (`compounds`/`compound_identifiers`/`compound_sources`/`pubchem_responses`),
  `conditions`/`compound_recommendations`, accepted `compound_measurements`, and
  (for the derivation reset) manually-curated `SpeciesCompoundRelationship` rows.

  Deletes are written against table names rather than schema modules on purpose:
  the crawl reset spans both the `Literature` and `Food` contexts, so keeping the
  whole ordered list in one auditable place beats coupling the two contexts. Table
  names come only from the compile-time module attributes below (no user input),
  so the interpolated `DELETE` statements are safe.
  """

  alias Mehungry.Repo

  # Full pipeline reset. Child tables first so the `scientific_studies` delete at
  # the end finds no dangling references (most of these also cascade, but we delete
  # them explicitly to report per-table counts). `species_compound_candidates` is
  # NOT a child of studies (it keys on species/compound), so it must be listed here
  # or it would be left orphaned of its citations.
  @crawl_tables ~w(
    compound_measurement_candidates
    study_full_texts
    pmc_fetch_attempts
    compound_recommendation_candidate_studies
    compound_recommendation_candidates
    study_entity_relations
    study_entity_mentions
    pubtator_responses
    pubtator_annotation_attempts
    species_compound_candidate_studies
    species_compound_candidates
    study_ingredients
    study_compounds
    entrez_responses
    literature_crawl_attempts
    scientific_studies
    literature_crawl_runs
    pubtator_annotation_runs
    candidate_derivation_runs
    recommendation_derivation_runs
    literature_extract_runs
  )

  @annotation_tables ~w(
    study_entity_relations
    study_entity_mentions
    pubtator_responses
    pubtator_annotation_attempts
    pubtator_annotation_runs
  )

  @extraction_tables ~w(
    compound_measurement_candidates
    study_full_texts
    pmc_fetch_attempts
    literature_extract_runs
  )

  @derivation_tables ~w(
    species_compound_candidate_studies
    species_compound_candidates
    candidate_derivation_runs
  )

  # Recommendation-candidate reset: wipe the derived candidates, their citations, and
  # the derivation runs. The curated `compound_recommendations` (advice) are preserved,
  # as are the `study_entity_relations` they were derived from.
  @recommendation_tables ~w(
    compound_recommendation_candidate_studies
    compound_recommendation_candidates
    recommendation_derivation_runs
  )

  @doc "Stage 1: wipe discovered studies and everything downstream. Keeps curated inputs."
  def reset_crawl, do: purge(@crawl_tables)

  @doc "Stage 2: wipe PubTator entity mentions + caches/ledger/runs. Keeps studies."
  def reset_annotation, do: purge(@annotation_tables)

  @doc "Stage FT: wipe PMC full texts, fetch attempts, and extracted measurement candidates. Keeps studies."
  def reset_extraction, do: purge(@extraction_tables)

  @doc """
  Stage 4: wipe derived candidates, their study citations, and derivation runs, plus
  the auto-promoted relationships (`source` other than `"manual"`). Manually-curated
  `SpeciesCompoundRelationship` facts are preserved.
  """
  def reset_derivation do
    Repo.transaction(fn ->
      counts = delete_tables(@derivation_tables)

      %{num_rows: rels} =
        Repo.query!(
          "DELETE FROM species_compound_relationships WHERE source IS DISTINCT FROM 'manual'"
        )

      Map.put(counts, "species_compound_relationships (auto)", rels)
    end)
    |> unwrap()
  end

  @doc "Stage 5: wipe derived recommendation candidates + citations + runs. Keeps curated advice."
  def reset_recommendations, do: purge(@recommendation_tables)

  defp purge(tables), do: Repo.transaction(fn -> delete_tables(tables) end) |> unwrap()

  defp delete_tables(tables) do
    Enum.reduce(tables, %{}, fn table, acc ->
      %{num_rows: n} = Repo.query!("DELETE FROM #{table}")
      Map.put(acc, table, n)
    end)
  end

  defp unwrap({:ok, counts}), do: counts
end
