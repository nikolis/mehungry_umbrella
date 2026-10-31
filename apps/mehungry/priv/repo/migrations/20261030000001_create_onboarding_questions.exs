defmodule Mehungry.Repo.Migrations.CreateOnboardingQuestions do
  use Ecto.Migration

  def change do
    create table(:onboarding_questions) do
      add :scope, :string, null: false
      add :professional_id, references(:users, on_delete: :delete_all)
      add :prompt_en, :string, null: false
      add :prompt_el, :string
      add :question_type, :string, null: false, default: "value"
      add :value_kind, :string, default: "text"
      add :required, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true
      add :source_key, :string
      # embeds_many :options (QuestionOption) — jsonb array of {key, label_en, label_el}.
      add :options, {:array, :map}, null: false, default: []

      timestamps()
    end

    create index(:onboarding_questions, [:scope, :professional_id, :position])
  end
end
