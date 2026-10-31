defmodule Mehungry.Onboarding do
  @moduledoc """
  Database-driven, admin-editable onboarding questions and the answers to them.

  Two surfaces share one engine (see `Onboarding.Question` for the `scope` model):

    * **Normal-user onboarding** — admin-authored `"user"` questions appended to
      the first-run wizard (`MehungryWeb.Onboarding.FormComponent`). Answers are
      stored against the platform user (`subject_type: "user"`), and surfaced to a
      nutritionist on that user's client file.
    * **Nutritionist client questionnaire** — an admin-authored `"client_default"`
      template that is **snapshotted on first use** (`ensure_client_questions/1`)
      into per-nutritionist `"client"` questions the nutritionist fully owns; the
      client self-fills them (`subject_type: "professional_client"`).

  Questions are facts here; the existing typed `Accounts.UserProfile` columns and
  `Professionals.ClientIntake` clinical fields are untouched.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Onboarding.{Question, Answer}
  alias Mehungry.Professionals.DietaryHistory.Fields

  # ── Questions ──────────────────────────────────────────────────────────────

  @doc "All questions in a scope (optionally a nutritionist's own set), ordered."
  def list_questions(scope, professional_id \\ nil) do
    scope
    |> scope_query(professional_id)
    |> order_by([q], asc: q.position, asc: q.id)
    |> Repo.all()
  end

  @doc "Only the active questions in a scope, ordered — what the wizard/form renders."
  def list_active_questions(scope, professional_id \\ nil) do
    scope
    |> scope_query(professional_id)
    |> where([q], q.active == true)
    |> order_by([q], asc: q.position, asc: q.id)
    |> Repo.all()
  end

  defp scope_query(scope, nil),
    do: from(q in Question, where: q.scope == ^scope and is_nil(q.professional_id))

  defp scope_query(scope, professional_id),
    do: from(q in Question, where: q.scope == ^scope and q.professional_id == ^professional_id)

  def get_question!(id), do: Repo.get!(Question, id)

  @doc "Fetch a question only if it belongs to this nutritionist's `client` set (else nil)."
  def get_client_question(professional_id, id),
    do: Repo.get_by(Question, id: id, scope: "client", professional_id: professional_id)

  def change_question(%Question{} = question, attrs \\ %{}),
    do: Question.changeset(question, attrs)

  def create_question(attrs) do
    %Question{}
    |> Question.changeset(put_default_position(attrs))
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  def delete_question(%Question{} = question), do: Repo.delete(question)

  @doc """
  Swap a question with its neighbour (`:up`/`:down`) within its own scope set,
  so the admin/nutritionist can reorder the questionnaire.
  """
  def move_question(%Question{} = question, direction) when direction in [:up, :down] do
    siblings = list_questions(question.scope, question.professional_id)
    idx = Enum.find_index(siblings, &(&1.id == question.id))
    swap_idx = if direction == :up, do: idx - 1, else: idx + 1

    if is_integer(idx) and swap_idx >= 0 and swap_idx < length(siblings) do
      other = Enum.at(siblings, swap_idx)

      Repo.transaction(fn ->
        set_position(question, other.position)
        set_position(other, question.position)
      end)

      :ok
    else
      :noop
    end
  end

  defp set_position(%Question{} = q, position),
    do: q |> Ecto.Changeset.change(position: position) |> Repo.update!()

  defp put_default_position(attrs) do
    scope = indiff_get(attrs, :scope)
    professional_id = indiff_get(attrs, :professional_id)

    position =
      case indiff_get(attrs, :position) do
        pos when pos in [nil, ""] -> next_position(scope, professional_id)
        pos -> pos
      end

    key = if Map.has_key?(attrs, "scope"), do: "position", else: :position
    Map.put(attrs, key, position)
  end

  defp next_position(scope, professional_id) do
    max =
      scope
      |> scope_query(professional_id)
      |> select([q], max(q.position))
      |> Repo.one()

    (max || -1) + 1
  end

  defp indiff_get(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  # ── Snapshot the admin default into a nutritionist's own set ─────────────────

  @doc """
  Copy the active `"client_default"` template into this nutritionist's own
  `"client"` questions the first time it's needed. Idempotent — a no-op once the
  nutritionist has any `"client"` rows, so later edits (theirs or the admin's)
  never clobber the snapshot. Returns the nutritionist's current question list.
  """
  def ensure_client_questions(professional_id) when not is_nil(professional_id) do
    Repo.transaction(fn ->
      case list_questions("client", professional_id) do
        [] -> seed_client_from_default(professional_id)
        existing -> existing
      end
    end)
    |> case do
      {:ok, questions} -> questions
    end
  end

  defp seed_client_from_default(professional_id) do
    for template <- list_active_questions("client_default") do
      %Question{}
      |> Question.changeset(%{
        scope: "client",
        professional_id: professional_id,
        prompt_en: template.prompt_en,
        prompt_el: template.prompt_el,
        question_type: template.question_type,
        value_kind: template.value_kind,
        required: template.required,
        position: template.position,
        active: template.active,
        source_key: template.source_key,
        options: Enum.map(template.options, &Map.from_struct/1)
      })
      |> Repo.insert!()
    end

    list_questions("client", professional_id)
  end

  # ── Answers ──────────────────────────────────────────────────────────────────

  @doc "Answers for a subject as a `%{question_id => %Answer{}}` map."
  def get_answers(subject_type, subject_id) do
    Answer
    |> where([a], a.subject_type == ^subject_type and a.subject_id == ^subject_id)
    |> Repo.all()
    |> Map.new(&{&1.question_id, &1})
  end

  @doc "Display-ready `{question, answer}` pairs for a user, ordered by position."
  def answers_for_user(user_id), do: display_answers("user", user_id)

  @doc "Display-ready `{question, answer}` pairs for a client, ordered by position."
  def answers_for_client(professional_client_id),
    do: display_answers("professional_client", professional_client_id)

  defp display_answers(subject_type, subject_id) do
    answers = subject_type |> get_answers(subject_id) |> Map.values()

    questions =
      case Enum.map(answers, & &1.question_id) do
        [] -> %{}
        ids -> from(q in Question, where: q.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})
      end

    answers
    |> Enum.map(&{Map.get(questions, &1.question_id), &1})
    |> Enum.sort_by(fn {q, a} -> {(q && q.position) || 9_999, a.id} end)
  end

  @doc """
  Upsert every answer in `params` (keyed by question id → `%{"value_text" =>,
  "selected_options" =>}`) for the given subject, validated against `questions`
  (the live question set). One row per question; re-submitting replaces it.
  """
  def upsert_answers(subject_type, subject_id, params, questions) do
    Repo.transaction(fn ->
      for question <- questions do
        answer_params = Map.get(params, to_string(question.id)) || %{}

        selected =
          answer_params
          |> Map.get("selected_options", [])
          |> List.wrap()
          |> Enum.reject(&(&1 in [nil, ""]))

        %Answer{}
        |> Answer.changeset(%{
          question_id: question.id,
          subject_type: subject_type,
          subject_id: subject_id,
          value_text: Map.get(answer_params, "value_text"),
          selected_options: selected,
          prompt_snapshot: question.prompt_en
        })
        |> Repo.insert!(
          on_conflict: {:replace, [:value_text, :selected_options, :prompt_snapshot, :updated_at]},
          conflict_target: [:question_id, :subject_type, :subject_id]
        )
      end
    end)
  end

  # ── Seeds ────────────────────────────────────────────────────────────────────

  @doc """
  Seed the admin `"client_default"` template from the legacy hardcoded
  `DietaryHistory.Fields` questionnaire (idempotent). `"user"` scope starts empty
  — the diet/language/calorie essentials stay hardcoded and the admin adds extras.
  Call from seeds / a release console after migrating.
  """
  def seed_defaults do
    if list_questions("client_default") == [] do
      Fields.detail_labels()
      |> Enum.with_index()
      |> Enum.each(fn {{key, label}, idx} ->
        create_question(%{
          scope: "client_default",
          prompt_en: label,
          prompt_el: label,
          question_type: "value",
          value_kind: "text",
          position: idx,
          source_key: key,
          active: true
        })
      end)
    end

    :ok
  end

  @doc false
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> String.slice(0, 80)
  end
end
