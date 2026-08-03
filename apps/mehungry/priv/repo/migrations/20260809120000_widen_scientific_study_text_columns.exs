defmodule Mehungry.Repo.Migrations.WidenScientificStudyTextColumns do
  use Ecto.Migration

  # PubMed titles/journal names/author lists frequently exceed 255 chars, which made
  # the Entrez crawl raise `22001 string_data_right_truncation` and discard the batch.
  # These are free-text fields with no reason to be length-capped — widen to text.
  def up do
    alter table(:scientific_studies) do
      modify :doi, :text
      modify :title, :text
      modify :journal, :text
      modify :authors, {:array, :text}
    end
  end

  def down do
    alter table(:scientific_studies) do
      modify :doi, :string
      modify :title, :string
      modify :journal, :string
      modify :authors, {:array, :string}
    end
  end
end
