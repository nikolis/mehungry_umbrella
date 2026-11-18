defmodule Mehungry.Repo.Migrations.CreateResearchSearch do
  use Ecto.Migration

  # Materialized view backing the nutritionist GLOBAL research search
  # (`FactMining.search_all_research/2`). One row per mined fact, carrying a
  # weighted tsvector document (findings=A, title=B, abstract=C) so a term that
  # appears as a finding outranks a title/abstract-only match, plus a
  # findings-only `finding_tsv` to tell "matched in a finding" from "matched in
  # abstract". Mirrors the `recipe_search` MV pattern; refreshed app-side after a
  # condition mine completes (NOT via DB triggers — see
  # `FactMining.refresh_research_search/0`), so `REFRESH … CONCURRENTLY` runs
  # post-commit outside the mine transaction.
  def up do
    execute("""
    CREATE MATERIALIZED VIEW research_search AS
    SELECT
      f.id            AS fact_row_id,
      f.condition_id  AS condition_id,
      c.name          AS condition_name,
      f.pmid          AS pmid,
      s.id            AS study_id,
      f.label         AS label,
      f.text          AS finding_text,
      (
        setweight(to_tsvector('english', unaccent(coalesce(f.text, '') || ' ' || coalesce(f.quote, ''))), 'A') ||
        setweight(to_tsvector('english', unaccent(coalesce(s.title, ''))), 'B') ||
        setweight(to_tsvector('english', unaccent(coalesce(s.abstract, ''))), 'C')
      ) AS document,
      to_tsvector('english', unaccent(coalesce(f.text, '') || ' ' || coalesce(f.quote, ''))) AS finding_tsv
    FROM condition_mined_facts f
    LEFT JOIN scientific_studies s ON s.pmid::text = f.pmid
    LEFT JOIN conditions c ON c.id = f.condition_id
    """)

    # FTS index for the WHERE/rank; unique index lets REFRESH … CONCURRENTLY run.
    create index("research_search", ["document"], using: :gin)
    create unique_index("research_search", [:fact_row_id])
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS research_search")
  end
end
