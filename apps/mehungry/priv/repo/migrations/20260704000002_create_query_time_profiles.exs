defmodule Mehungry.Repo.Migrations.CreateQueryTimeProfiles do
  use Ecto.Migration

  def change do
    create table(:query_time_profiles) do
      add :fingerprint, :string, null: false
      add :query, :text, null: false
      add :source, :string
      add :period_start, :utc_datetime, null: false
      add :min, :float
      add :avg, :float
      add :max, :float
      add :p95, :float
      add :sample_count, :integer, default: 0
    end

    create index(:query_time_profiles, [:fingerprint, :period_start])
    create index(:query_time_profiles, [:period_start])
  end
end
