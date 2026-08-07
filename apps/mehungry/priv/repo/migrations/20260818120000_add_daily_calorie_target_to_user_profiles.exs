defmodule Mehungry.Repo.Migrations.AddDailyCalorieTargetToUserProfiles do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      add :daily_calorie_target, :integer
    end
  end
end
