defmodule Mehungry.Repo.Migrations.AddLanguagePreferenceToUserProfiles do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      add :language_preference, :string, default: "en", null: false
    end
  end
end
