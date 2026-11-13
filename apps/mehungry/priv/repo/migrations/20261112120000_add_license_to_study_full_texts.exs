defmodule Mehungry.Repo.Migrations.AddLicenseToStudyFullTexts do
  use Ecto.Migration

  @moduledoc """
  Full-text licensing + integrity columns for `study_full_texts`.

  The extractor historically stored the verbatim PMC body of any linkable paper with
  no license signal and (on a loose PMID→PMCID match) sometimes the *wrong* article's
  text. These columns let the reader gate on reuse rights + content verification:

    * `license` / `license_url` — the paper's reuse license (parsed from the JATS
      `<permissions><license>`); drives whether the verbatim body may be displayed.
    * `full_text_displayable` — the explicit UI gate. Default **false** so nothing is
      served until positively verified + licensed for reuse.
    * `integrity_status` — `verified` | `pending_review` | `mismatch` (body ≠ cited paper).
  """

  def change do
    alter table(:study_full_texts) do
      add :license, :string
      add :license_url, :string
      add :full_text_displayable, :boolean, default: false, null: false
      add :integrity_status, :string, default: "pending_review", null: false
    end

    # The reader queries full text by (displayable, verified) — index the gate.
    create index(:study_full_texts, [:full_text_displayable, :integrity_status])
  end
end
