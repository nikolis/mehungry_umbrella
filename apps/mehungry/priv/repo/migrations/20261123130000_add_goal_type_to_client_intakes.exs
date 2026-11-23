defmodule Mehungry.Repo.Migrations.AddGoalTypeToClientIntakes do
  use Ecto.Migration

  # The direction of the client's goal — "lose" | "maintain" | "gain" — picked by
  # the nutritionist. Drives the calorie band a plan must land in when no explicit
  # target_kcal is set. Nullable: nil is treated as "maintain".
  def change do
    alter table(:client_intakes) do
      add :goal_type, :string
    end
  end
end
