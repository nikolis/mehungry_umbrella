defmodule Mehungry.Onboarding.QuestionOption do
  @moduledoc """
  One choice of a multiple-choice `Onboarding.Question`, embedded as a JSON object
  in the question's `options` array.

  `key` is the stable identifier stored in an answer's `selected_options`; it is
  auto-slugged from the English label when blank and then preserved across edits
  (so re-labelling a choice never invalidates answers that referenced it).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label_en, :string
    field :label_el, :string
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:key, :label_en, :label_el])
    |> validate_required([:label_en])
    |> maybe_put_key()
  end

  defp maybe_put_key(changeset) do
    case get_field(changeset, :key) do
      key when is_binary(key) and key != "" ->
        changeset

      _ ->
        case get_field(changeset, :label_en) do
          label when is_binary(label) and label != "" ->
            put_change(changeset, :key, Mehungry.Onboarding.slugify(label))

          _ ->
            changeset
        end
    end
  end

  @doc "Locale-aware label, falling back to the English label."
  def label(%__MODULE__{label_en: en, label_el: el}, "el"),
    do: if(el in [nil, ""], do: en, else: el)

  def label(%__MODULE__{label_en: en}, _locale), do: en
end
