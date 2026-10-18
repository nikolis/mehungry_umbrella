defmodule Mehungry.Repo.Migrations.CreateHistoryDayNotes do
  use Ecto.Migration

  # Per-day private journal line on the calendar (symptoms / how I felt / energy).
  # One row per user per day; blank notes are deleted rather than stored.
  def change do
    create table(:history_day_notes) do
      add :date, :date, null: false
      add :body, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:history_day_notes, [:user_id, :date])
  end
end
