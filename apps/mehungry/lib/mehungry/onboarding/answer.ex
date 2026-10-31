defmodule Mehungry.Onboarding.Answer do
  @moduledoc """
  One subject's answer to one `Onboarding.Question`.

  Generic across both onboarding surfaces via `(subject_type, subject_id)`:
  `"user"` → a `users.id` (the normal-user wizard), `"professional_client"` → a
  `professional_clients.id` (a nutritionist's client self-fill). `value_text`
  holds free-form answers; `selected_options` holds the chosen option keys for
  choice questions. `prompt_snapshot` denormalizes the question prompt so an
  answer stays readable even if the question is later deleted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Onboarding.Question

  @subject_types ~w(user professional_client)

  schema "onboarding_answers" do
    belongs_to :question, Question
    field :subject_type, :string
    field :subject_id, :id
    field :value_text, :string
    field :selected_options, {:array, :string}, default: []
    field :prompt_snapshot, :string

    timestamps()
  end

  def subject_types, do: @subject_types

  @doc false
  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [
      :question_id,
      :subject_type,
      :subject_id,
      :value_text,
      :selected_options,
      :prompt_snapshot
    ])
    |> validate_required([:question_id, :subject_type, :subject_id])
    |> validate_inclusion(:subject_type, @subject_types)
    |> foreign_key_constraint(:question_id)
    |> unique_constraint([:question_id, :subject_type, :subject_id],
      name: :onboarding_answers_unique_index
    )
  end
end
