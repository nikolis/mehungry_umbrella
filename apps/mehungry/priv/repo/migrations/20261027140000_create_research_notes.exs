defmodule Mehungry.Repo.Migrations.CreateResearchNotes do
  use Ecto.Migration

  def change do
    create table(:research_notes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :body, :text

      # The research context the note was captured under. Both nilify on delete so
      # a note survives (as a plain record) if its condition/study is later removed.
      add :condition_id, references(:conditions, on_delete: :nilify_all)
      add :study_id, references(:scientific_studies, on_delete: :nilify_all)

      # Provenance into the source claim (claims live in StudyAnalysis jsonb — not a
      # FK) + the reader deep-link anchors + verbatim evidence snapshot, captured at
      # save time so "open in text" and the quote survive later re-analysis.
      add :claim_id, :string
      add :section_id, :string
      add :paragraph_id, :string
      add :quoted_text, :text

      add :details, :map, default: %{}

      timestamps()
    end

    create index(:research_notes, [:user_id])
    create index(:research_notes, [:user_id, :condition_id])

    # Saving the same suggestion twice is a no-op/toggle; custom notes (claim_id
    # NULL) are never deduped.
    create unique_index(:research_notes, [:user_id, :study_id, :claim_id],
             where: "claim_id IS NOT NULL",
             name: :research_notes_user_study_claim_index
           )
  end
end
