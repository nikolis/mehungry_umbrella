defmodule Mehungry.Repo.Migrations.CreateTutorInvitations do
  use Ecto.Migration

  def change do
    create table(:tutor_invitations) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :message, :text

      timestamps()
    end

    create unique_index(:tutor_invitations, [:professional_id, :client_id])
    create index(:tutor_invitations, [:client_id])
    create index(:tutor_invitations, [:status])
  end
end
