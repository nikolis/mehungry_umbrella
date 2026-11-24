defmodule Mehungry.Repo.Migrations.AddCountryToUserProfiles do
  use Ecto.Migration

  # The country a person lives in (ISO-3166 alpha-2), used to suggest fruit that is in
  # season there (Mehungry.Food.SeasonalAvailability). Defaults to Greece, where almost
  # all current users are.
  def change do
    alter table(:user_profiles) do
      add :country, :string, size: 2, null: false, default: "GR"
    end
  end
end
