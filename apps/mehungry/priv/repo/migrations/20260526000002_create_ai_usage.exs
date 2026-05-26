defmodule Mehungry.Repo.Migrations.CreateAiUsage do
  use Ecto.Migration

  def change do
    create table(:ai_usage) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :feature, :string, null: false
      add :used_at, :naive_datetime, null: false

      timestamps()
    end

    create index(:ai_usage, [:user_id, :feature])
    create index(:ai_usage, [:used_at])
  end
end
