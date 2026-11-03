defmodule Mehungry.Repo.Migrations.AddMeasurementsToConsultationNotes do
  use Ecto.Migration

  def change do
    alter table(:consultation_notes) do
      add :body_fat_percentage, :float
      add :waist_cm, :float
      add :muscle_mass_kg, :float
      add :bmi, :float
      add :bmr_kcal, :integer
    end
  end
end
