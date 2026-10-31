defmodule Mehungry.Repo.Migrations.AddJournalAuthorityToScientificStudies do
  use Ecto.Migration

  # Additive: the journal-authority signal for the nutritionist research search.
  # `issn` is the universal journal join key; `citation_status` carries the
  # MedlineCitation @Status ("MEDLINE" = vetted/indexed) — our public-domain
  # authority marker. Both are backfilled from retained `entrez_responses`.
  def change do
    alter table(:scientific_studies) do
      add :issn, :string
      add :citation_status, :string
    end
  end
end
