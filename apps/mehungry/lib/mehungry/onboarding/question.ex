defmodule Mehungry.Onboarding.Question do
  @moduledoc """
  A single admin/nutritionist-authored onboarding question, in one of three
  `scope`s:

    * `"user"` — appended to the normal-user onboarding wizard (admin-owned,
      `professional_id` nil).
    * `"client_default"` — the admin-owned default template for a nutritionist's
      client questionnaire (`professional_id` nil).
    * `"client"` — a single nutritionist's own, snapshot-seeded, editable copy
      (`professional_id` set).

  A question is either a free-form `value` input (`value_kind` text/number) or a
  `single_choice`/`multi_choice` question whose choices are the embedded
  `options`. Prompts and option labels carry both an English and a Greek string
  (EN is the fallback). `source_key` is a stable slug carried from the template
  into a nutritionist's snapshot so answers keyed off it survive re-seeding.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Onboarding.QuestionOption

  @scopes ~w(user client_default client)
  @types ~w(value single_choice multi_choice)
  @value_kinds ~w(text number)

  schema "onboarding_questions" do
    field :scope, :string
    field :professional_id, :id
    field :prompt_en, :string
    field :prompt_el, :string
    field :question_type, :string, default: "value"
    field :value_kind, :string, default: "text"
    field :required, :boolean, default: false
    field :position, :integer, default: 0
    field :active, :boolean, default: true
    field :source_key, :string

    embeds_many :options, QuestionOption, on_replace: :delete

    timestamps()
  end

  def scopes, do: @scopes
  def types, do: @types
  def value_kinds, do: @value_kinds

  def choice_type?(type), do: type in ["single_choice", "multi_choice"]

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :scope,
      :professional_id,
      :prompt_en,
      :prompt_el,
      :question_type,
      :value_kind,
      :required,
      :position,
      :active,
      :source_key
    ])
    |> cast_embed(:options,
      with: &QuestionOption.changeset/2,
      sort_param: :options_sort,
      drop_param: :options_drop
    )
    |> validate_required([:scope, :prompt_en, :question_type])
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:question_type, @types)
    |> validate_inclusion(:value_kind, @value_kinds)
    |> validate_choice_options()
    |> maybe_put_source_key()
  end

  defp validate_choice_options(changeset) do
    if choice_type?(get_field(changeset, :question_type)) and
         (get_field(changeset, :options) || []) == [] do
      add_error(changeset, :options, "add at least one choice for a multiple-choice question")
    else
      changeset
    end
  end

  defp maybe_put_source_key(changeset) do
    case get_field(changeset, :source_key) do
      key when is_binary(key) and key != "" ->
        changeset

      _ ->
        case get_field(changeset, :prompt_en) do
          prompt when is_binary(prompt) and prompt != "" ->
            put_change(changeset, :source_key, Mehungry.Onboarding.slugify(prompt))

          _ ->
            changeset
        end
    end
  end

  @doc "Locale-aware prompt, falling back to the English prompt."
  def prompt(%__MODULE__{prompt_en: en, prompt_el: el}, "el"),
    do: if(el in [nil, ""], do: en, else: el)

  def prompt(%__MODULE__{prompt_en: en}, _locale), do: en
end
