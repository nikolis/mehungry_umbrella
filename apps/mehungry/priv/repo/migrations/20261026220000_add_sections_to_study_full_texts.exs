defmodule Mehungry.Repo.Migrations.AddSectionsToStudyFullTexts do
  use Ecto.Migration

  # Additive: the structured section/paragraph outline of a paper's open-access
  # full text (title + absolute char offsets + paragraph text), carried by the
  # enriched `mehungry_extractor` `/analyze` response. Powers the nutritionist
  # research reader (section deep-links + claim-span highlighting). Defaults to an
  # empty list so existing rows and abstract-only papers are unaffected.
  # jsonb holding the sections JSON array — loaded as `{:array, :map}` in the
  # schema (same convention as `study_analyses.claims`). Nullable; the changeset
  # always sets it, defaulting to `[]`.
  def change do
    alter table(:study_full_texts) do
      add :sections, :map
    end
  end
end
