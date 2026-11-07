defmodule Mehungry.Repo.Migrations.CreateProgressPeriods do
  use Ecto.Migration

  def change do
    create table(:progress_periods) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "self"
      add :professional_id, references(:users, on_delete: :nilify_all)
      add :started_on, :date, null: false
      add :ended_on, :date
      add :tracked_metrics, {:array, :string}, null: false, default: ["weight_kg"]
      add :goals, :map, null: false, default: %{}
      add :shared_with_nutritionist, :boolean, null: false, default: false
      add :title, :string
      add :notes, :text
      add :height_m, :float
      add :sex, :string
      add :age, :integer

      timestamps()
    end

    # One active (ended_on IS NULL) period per user — the arbiter for every
    # close-then-open transition (reset, nutritionist alignment).
    create unique_index(:progress_periods, [:user_id],
             where: "ended_on IS NULL",
             name: :progress_periods_one_active_per_user
           )

    create index(:progress_periods, [:user_id, :started_on])
  end
end
