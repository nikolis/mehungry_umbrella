defmodule Mehungry.Repo.Migrations.AddFollowedBlueprintToUserProfiles do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      # The meal blueprint the user is currently "following" on their calendar.
      # Nullable — most users follow none; nilified if the blueprint is deleted.
      add :followed_blueprint_id,
          references(:meal_blueprints, on_delete: :nilify_all),
          null: true
    end

    create index(:user_profiles, [:followed_blueprint_id])
  end
end
