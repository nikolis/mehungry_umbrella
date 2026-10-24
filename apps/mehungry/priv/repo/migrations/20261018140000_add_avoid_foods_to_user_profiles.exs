defmodule Mehungry.Repo.Migrations.AddAvoidFoodsToUserProfiles do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      # Personal free-text "foods I avoid" list, surfaced on the calendar to flag
      # logged meals that contain one. Mirrors a blueprint's `avoid_foods`, but
      # user-owned and not gated behind nutritionist blueprint authoring.
      add :avoid_foods, {:array, :string}, default: [], null: false
    end
  end
end
