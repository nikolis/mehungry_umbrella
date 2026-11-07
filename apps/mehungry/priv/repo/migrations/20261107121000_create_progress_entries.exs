defmodule Mehungry.Repo.Migrations.CreateProgressEntries do
  use Ecto.Migration

  def change do
    create table(:progress_entries) do
      add :progress_period_id, references(:progress_periods, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :entry_date, :date, null: false
      add :weight_kg, :float
      add :waist_cm, :float
      add :body_fat_percentage, :float
      add :muscle_mass_kg, :float
      add :bmi, :float
      add :bmr_kcal, :integer
      add :note, :text

      timestamps()
    end

    # One diary entry per date per period — logging the same day again upserts.
    create unique_index(:progress_entries, [:progress_period_id, :entry_date])
    create index(:progress_entries, [:user_id])
  end
end
