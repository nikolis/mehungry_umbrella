defmodule Mehungry.Repo.Migrations.AddIntakeDemographicsForEnergyCalc do
  use Ecto.Migration

  # Structured inputs the Mifflin–St Jeor BMR + TDEE formulas need but that were
  # previously only free text in `details` (sex was captured nowhere). Nullable:
  # existing rows (and CSV imports that carry their own BMR/TDEE) stay valid.
  def up do
    alter table(:client_intakes) do
      add :sex, :string
      add :age, :integer
      add :activity_level, :string
    end
  end

  def down do
    alter table(:client_intakes) do
      remove :sex
      remove :age
      remove :activity_level
    end
  end
end
