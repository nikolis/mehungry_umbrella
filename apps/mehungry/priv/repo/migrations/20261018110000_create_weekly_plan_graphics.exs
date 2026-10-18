defmodule Mehungry.Repo.Migrations.CreateWeeklyPlanGraphics do
  use Ecto.Migration

  def change do
    create table(:weekly_plan_graphics) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :week_start, :date, null: false
      add :locale, :string
      add :goal_label, :string
      add :image_url, :string, null: false
      add :macros, :map, default: %{}
      add :caption, :text

      timestamps(updated_at: false)
    end

    create index(:weekly_plan_graphics, [:user_id, :week_start])

    alter table(:posts) do
      add :weekly_plan_graphic_id,
          references(:weekly_plan_graphics, on_delete: :nilify_all)
    end

    create index(:posts, [:weekly_plan_graphic_id])
  end
end
