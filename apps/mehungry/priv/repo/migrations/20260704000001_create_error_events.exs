defmodule Mehungry.Repo.Migrations.CreateErrorEvents do
  use Ecto.Migration

  def change do
    create table(:error_events) do
      add :fingerprint, :string, null: false
      add :kind, :string
      add :source, :string, null: false
      add :reason, :text
      add :stacktrace, :text
      add :context, :map, default: %{}
      add :count, :integer, default: 1, null: false
      add :first_seen, :utc_datetime, null: false
      add :last_seen, :utc_datetime, null: false
    end

    create unique_index(:error_events, [:fingerprint])
    create index(:error_events, [:last_seen])
  end
end
