defmodule Mehungry.Literature.StudyFullText do
  @moduledoc """
  Fetched PMC open-access full text for a `ScientificStudy` — the source the
  measurement extractor reads (composition numbers live in results/tables, not the
  abstract). One row per study.

  `sections` holds the structured outline the enriched `mehungry_extractor`
  `/analyze` response carries for a full-text paper: an ordered list of section
  maps (`section_id`, `index`, `title`, `start_char`, `end_char`, `paragraphs`),
  each paragraph `{ paragraph_id, start_char, end_char, text }` with absolute
  offsets into the canonical document text. This powers the nutritionist research
  reader (per-section/paragraph anchors + claim-span highlighting). Empty for
  abstract-only papers.

  ## Licensing + integrity gate

  The verbatim body is only shown when it is both **reusable** and **verified**:

    * `license` / `license_url` — the paper's reuse license, parsed from the JATS
      `<permissions><license>` (normalized by `Mehungry.Literature.License`). Most
      PMC full text is *not* freely redistributable; only `cc0`/`cc-by`/`cc-by-sa`
      may be displayed verbatim in the (commercial) product.
    * `full_text_displayable` — the explicit UI gate. Default `false`; set true only
      for a reusable license on a content-verified row. The reader keys on this.
    * `integrity_status` — `verified` | `pending_review` | `mismatch`. The extractor
      used to substitute a different article's text when the real full text wasn't in
      PMC; `mismatch` rows (body ≠ cited paper) are purged, not shown.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.ScientificStudy

  schema "study_full_texts" do
    field :pmcid, :string
    field :source, :string
    field :body, :string
    field :sections, {:array, :map}, default: []
    field :retrieved_at, :utc_datetime

    field :license, :string
    field :license_url, :string
    field :full_text_displayable, :boolean, default: false
    field :integrity_status, :string, default: "pending_review"

    belongs_to :study, ScientificStudy

    timestamps()
  end

  @integrity_statuses ~w(verified pending_review mismatch)

  @doc "The valid `integrity_status` values."
  def integrity_statuses, do: @integrity_statuses

  def changeset(full_text, attrs) do
    full_text
    |> cast(attrs, [
      :study_id,
      :pmcid,
      :source,
      :body,
      :sections,
      :retrieved_at,
      :license,
      :license_url,
      :full_text_displayable,
      :integrity_status
    ])
    |> validate_required([:study_id, :body])
    |> validate_inclusion(:integrity_status, @integrity_statuses)
    |> unique_constraint(:study_id)
  end
end
