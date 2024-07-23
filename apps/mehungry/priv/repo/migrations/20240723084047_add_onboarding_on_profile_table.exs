defmodule Mehungry.Repo.Migrations.AddOnboardingOnProfileTable do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      add :onboarding_level, :integer
    end
  end
end
