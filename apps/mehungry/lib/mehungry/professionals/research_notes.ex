defmodule Mehungry.Professionals.ResearchNotes do
  @moduledoc """
  Per-nutritionist research notes — the persistence behind the research search's
  **Suggested notes** (see `docs/features/professionals/research_notes.md`).

  A note is owned by a single nutritionist `User` and is either a **saved
  suggestion** (`kind: "suggested"`, carrying provenance into a `StudyAnalysis`
  claim) or a **custom** free-text note. Every write is scoped to the owning
  `user_id` — the web layer passes the authenticated user, never a client value.
  Saved suggestions are idempotent/toggleable, keyed on `(user_id, study_id,
  claim_id)`.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Professionals.ResearchNote

  @doc """
  Build the `save_suggested/2` attrs snapshot from a `StudyAnalysis` claim map
  (the jsonb shape) — the body (rendered prose) + the reader deep-link anchors +
  verbatim evidence, captured so they survive later re-analysis. Shared by every
  surface that offers a Save (the condition results card + the reader widget).
  """
  def suggested_attrs_from_claim(condition_id, study_id, claim) do
    %{
      condition_id: condition_id,
      study_id: study_id,
      claim_id: claim["claim_id"],
      body: claim_body(claim),
      section_id: evidence_field(claim, "section_id"),
      paragraph_id: evidence_field(claim, "paragraph_id"),
      quoted_text: evidence_field(claim, "quoted_text")
    }
  end

  defp claim_body(claim) do
    "#{endpoint(claim, "subject")} — #{claim["predicate"]} — #{endpoint(claim, "object")} (#{claim["polarity"]})"
  end

  defp endpoint(claim, side),
    do: claim["#{side}_label"] || claim["#{side}_name"] || claim["#{side}_text"]

  defp evidence_field(%{"evidence" => [first | _]}, key) when is_map(first), do: first[key]
  defp evidence_field(_, _), do: nil

  @doc """
  Save a suggested note (idempotent). `attrs` carries the claim snapshot
  (`study_id`, `claim_id`, `body`, `section_id`, `paragraph_id`, `quoted_text`)
  and the `condition_id` context. Re-saving the same claim returns the existing
  row instead of erroring on the unique index.
  """
  def save_suggested(user_id, attrs) do
    attrs = attrs |> stringify() |> Map.merge(%{"user_id" => user_id, "kind" => "suggested"})

    case get_suggested(user_id, attrs["study_id"], attrs["claim_id"]) do
      %ResearchNote{} = existing -> {:ok, existing}
      nil -> %ResearchNote{} |> ResearchNote.changeset(attrs) |> Repo.insert()
    end
  end

  @doc "Create a custom (free-text) note owned by `user_id`."
  def create_custom(user_id, attrs) do
    attrs = attrs |> stringify() |> Map.merge(%{"user_id" => user_id, "kind" => "custom"})
    %ResearchNote{} |> ResearchNote.changeset(attrs) |> Repo.insert()
  end

  @doc "Remove a saved suggestion by its source claim (the card's Save toggle)."
  def delete_suggested(user_id, study_id, claim_id) do
    {count, _} =
      ResearchNote
      |> where(user_id: ^user_id, study_id: ^study_id, claim_id: ^claim_id, kind: "suggested")
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc "Delete one of the user's notes by id (ownership-scoped)."
  def delete_note(user_id, id) do
    {count, _} = ResearchNote |> where(user_id: ^user_id, id: ^id) |> Repo.delete_all()
    {:ok, count}
  end

  @doc "All of a user's notes, newest first, with condition + study preloaded."
  def list_for_user(user_id) do
    ResearchNote
    |> where(user_id: ^user_id)
    |> order_by([n], desc: n.inserted_at)
    |> preload([:condition, :study])
    |> Repo.all()
  end

  @doc "A user's notes for one study, newest first (both suggested + custom)."
  def list_for_user_and_study(user_id, study_id) do
    ResearchNote
    |> where(user_id: ^user_id, study_id: ^study_id)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  @doc "A user's notes for one condition, newest first (condition + study preloaded)."
  def list_for_user_and_condition(user_id, condition_id) do
    ResearchNote
    |> where(user_id: ^user_id, condition_id: ^condition_id)
    |> order_by([n], desc: n.inserted_at)
    |> preload([:condition, :study])
    |> Repo.all()
  end

  @doc """
  The `{study_id, claim_id}` pairs the user has already saved under `condition_id`
  — a `MapSet` so a results card can cheaply show per-claim "Saved" state.
  """
  def saved_claim_keys(user_id, condition_id) do
    ResearchNote
    |> where(user_id: ^user_id, condition_id: ^condition_id, kind: "suggested")
    |> select([n], {n.study_id, n.claim_id})
    |> Repo.all()
    |> MapSet.new()
  end

  defp get_suggested(_user_id, nil, _claim_id), do: nil
  defp get_suggested(_user_id, _study_id, nil), do: nil

  defp get_suggested(user_id, study_id, claim_id) do
    Repo.get_by(ResearchNote,
      user_id: user_id,
      study_id: study_id,
      claim_id: claim_id,
      kind: "suggested"
    )
  end

  defp stringify(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
