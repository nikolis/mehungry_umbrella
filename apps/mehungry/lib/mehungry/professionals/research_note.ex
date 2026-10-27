defmodule Mehungry.Professionals.ResearchNote do
  @moduledoc """
  A nutritionist's personal note taken against the research search, either a
  **saved suggestion** (`kind: "suggested"` — provenance into a `StudyAnalysis`
  claim) or a **custom** free-text note (`kind: "custom"`).

  Owned directly by the nutritionist `User` (the `user_recipes` per-user
  pattern). Private to the owner — there is no sharing. Claims live in
  `StudyAnalysis` jsonb, so `claim_id` is a plain string (provenance), not a FK;
  `section_id` / `paragraph_id` / `quoted_text` snapshot the reader deep-link
  anchor + evidence at save time so they survive later re-analysis.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Health.Condition
  alias Mehungry.Literature.ScientificStudy

  @kinds ~w(suggested custom)

  def kinds, do: @kinds

  schema "research_notes" do
    field :kind, :string
    field :body, :string
    field :claim_id, :string
    field :section_id, :string
    field :paragraph_id, :string
    field :quoted_text, :string
    field :details, :map, default: %{}

    belongs_to :user, User
    belongs_to :condition, Condition
    belongs_to :study, ScientificStudy

    timestamps()
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :user_id,
      :kind,
      :body,
      :condition_id,
      :study_id,
      :claim_id,
      :section_id,
      :paragraph_id,
      :quoted_text,
      :details
    ])
    |> validate_required([:user_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_claim_id_presence()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:condition_id)
    |> foreign_key_constraint(:study_id)
    |> unique_constraint([:user_id, :study_id, :claim_id],
      name: :research_notes_user_study_claim_index
    )
  end

  # Suggested notes must carry their source claim (that's what makes them
  # dedupable + deep-linkable); custom notes never do.
  defp validate_claim_id_presence(changeset) do
    case get_field(changeset, :kind) do
      "suggested" -> validate_required(changeset, [:claim_id, :study_id])
      _ -> changeset
    end
  end
end
