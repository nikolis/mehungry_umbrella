defmodule Mehungry.Repo.Migrations.AddPublishedMealPlanToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :published_meal_plan_id,
          references(:published_meal_plans, on_delete: :nilify_all)
    end

    create index(:posts, [:published_meal_plan_id])
  end
end
