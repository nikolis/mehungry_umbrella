defmodule Mehungry.Repo.Migrations.AddCircumferenceMeasurementsToConsultationNotes do
  use Ecto.Migration

  def change do
    alter table(:consultation_notes) do
      add :hands_cm, :float
      add :glutes_cm, :float
      add :feet_cm, :float
    end
  end
end
