defmodule Mehungry.Repo.Migrations.CreatePublishedMealPlans do
  use Ecto.Migration

  def change do
    create table(:published_meal_plans) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :slug, :string, null: false
      add :title, :string, null: false
      add :goal_label, :string
      add :locale, :string
      add :week_start, :date

      # Self-contained, immutable snapshot of the week (so the public page never
      # changes when the author later edits their live calendar, and carries no
      # live PII). `days` is an array of day maps, each with ordered meal items
      # (recipe items keep `recipe_id` so the page can link to `/browse/:id`).
      add :days, {:array, :map}, null: false, default: []
      add :macros, :map, null: false, default: %{}
      add :grocery, {:array, :string}, null: false, default: []
      add :summary_text, :text
      add :og_image_url, :string
      add :recipe_count, :integer, null: false, default: 0

      add :visibility, :string, null: false, default: "public"
      add :published_at, :utc_datetime

      timestamps()
    end

    create unique_index(:published_meal_plans, [:slug])
    create index(:published_meal_plans, [:user_id])
    create index(:published_meal_plans, [:visibility, :published_at])
  end
end
