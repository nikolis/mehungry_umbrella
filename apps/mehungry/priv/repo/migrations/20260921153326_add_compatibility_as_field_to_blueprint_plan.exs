defmodule Mehungry.Repo.Migrations.AddCompatibilityAsFieldToBlueprintPlan do
  use Ecto.Migration

  def change do
    alter table(:meal_blueprint_plans) do
      add(:compatibility, :map, default: %{})
    end
  end
end
