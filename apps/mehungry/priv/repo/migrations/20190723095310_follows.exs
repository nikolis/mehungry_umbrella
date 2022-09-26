defmodule MehungryServer.Repo.Migrations.Follows do
  use Ecto.Migration

  def change do
    create table(:follows) do
      add :user_id, references(:users, on_delete: :nothing), primary_key: true
      add :follow_id, references(:users, on_delete: :nothing), primary_key: true

      timestamps()
    end
  end
end
