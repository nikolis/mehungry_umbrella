defmodule Mehungry.Repo.Migrations.DedupeClientIntakeAge do
  use Ecto.Migration

  @moduledoc """
  Age was being stored twice on a client intake: once in the structured
  `age` integer column (shown in the intake metrics, and the input to
  BMR/TDEE), and again as a free-text `details["age"]` questionnaire key —
  the CSV importer routed the sheet's "ΗΛΙΚΙΑ:" column into `details`. The
  client record view rendered both, so age appeared in both "Intake" and
  "Questionnaire".

  The importer now routes age to the typed `:age` column and the questionnaire
  field list no longer includes `age`. This migration reconciles existing rows:

    1. Backfill the typed `age` from `details->>'age'` where `age` is still
       null and the detail holds a plain, in-range integer.
    2. Drop the redundant `age` key from `details` everywhere.
  """

  def up do
    # 1. Promote a clean integer detail into the typed column (only when empty).
    execute("""
    UPDATE client_intakes
    SET age = (details->>'age')::int
    WHERE age IS NULL
      AND details ? 'age'
      AND details->>'age' ~ '^[0-9]+$'
      AND (details->>'age')::int > 0
      AND (details->>'age')::int < 130
    """)

    # 2. Remove the duplicate key from the JSONB map (idempotent).
    execute("""
    UPDATE client_intakes
    SET details = details - 'age'
    WHERE details ? 'age'
    """)
  end

  def down do
    # Irreversible: the value is preserved in the typed `age` column, and we
    # deliberately do not recreate the duplicate detail key. No-op.
    :ok
  end
end
