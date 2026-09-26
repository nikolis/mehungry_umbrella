defmodule Mehungry.Repo.Migrations.BackfillResultStudyProvenance do
  use Ecto.Migration

  # Seed the new frozen result↔study join tables from the studies already linked to
  # each *promoted* candidate, via its `promoted_*_id` forward pointer. This is the
  # one-time migration of existing conclusions onto durable provenance; from here on
  # the join is populated at promotion. Idempotent (ON CONFLICT DO NOTHING). Manual
  # recommendations with no backing candidate rely on `source_reference` instead and
  # are intentionally not touched here.
  def up do
    execute("""
    INSERT INTO compound_recommendation_studies (recommendation_id, study_id, inserted_at, updated_at)
    SELECT c.promoted_recommendation_id, cs.study_id, (now() at time zone 'utc'), (now() at time zone 'utc')
    FROM compound_recommendation_candidates c
    JOIN compound_recommendation_candidate_studies cs ON cs.candidate_id = c.id
    WHERE c.status = 'promoted' AND c.promoted_recommendation_id IS NOT NULL
    ON CONFLICT DO NOTHING
    """)

    execute("""
    INSERT INTO species_compound_relationship_studies (relationship_id, study_id, inserted_at, updated_at)
    SELECT c.promoted_relationship_id, cs.study_id, (now() at time zone 'utc'), (now() at time zone 'utc')
    FROM species_compound_candidates c
    JOIN species_compound_candidate_studies cs ON cs.candidate_id = c.id
    WHERE c.status = 'promoted' AND c.promoted_relationship_id IS NOT NULL
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM compound_recommendation_studies")
    execute("DELETE FROM species_compound_relationship_studies")
  end
end
