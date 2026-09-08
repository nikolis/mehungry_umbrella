defmodule Mehungry.Repo.Migrations.CreateConsultationNotes do
  use Ecto.Migration

  def change do
    create table(:consultation_notes) do
      add :professional_client_id,
          references(:professional_clients, on_delete: :delete_all),
          null: false

      add :appointment_id, references(:professional_appointments, on_delete: :nilify_all)

      add :visit_number, :integer
      add :visit_date, :date
      add :modality, :string, default: "in_person"
      add :body, :text
      add :todo, :text
      add :weight_kg, :float
      add :details, :map, default: %{}

      timestamps()
    end

    create index(:consultation_notes, [:professional_client_id])
    create index(:consultation_notes, [:appointment_id])
  end
end
