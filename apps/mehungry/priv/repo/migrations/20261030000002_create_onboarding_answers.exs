defmodule Mehungry.Repo.Migrations.CreateOnboardingAnswers do
  use Ecto.Migration

  def change do
    create table(:onboarding_answers) do
      add :question_id, references(:onboarding_questions, on_delete: :delete_all), null: false
      # Polymorphic subject: "user" -> users.id, "professional_client" -> professional_clients.id.
      add :subject_type, :string, null: false
      add :subject_id, :bigint, null: false
      add :value_text, :text
      add :selected_options, {:array, :string}, null: false, default: []
      add :prompt_snapshot, :string

      timestamps()
    end

    create index(:onboarding_answers, [:subject_type, :subject_id])

    create unique_index(:onboarding_answers, [:question_id, :subject_type, :subject_id],
             name: :onboarding_answers_unique_index
           )
  end
end
