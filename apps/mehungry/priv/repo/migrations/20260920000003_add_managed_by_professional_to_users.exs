defmodule Mehungry.Repo.Migrations.AddManagedByProfessionalToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Set when a professional creates a login-less "managed" client account on
      # the client's behalf (no password). Cleared once the client claims the
      # account and sets their own credentials. NULL for all normal accounts.
      add :managed_by_professional_id, references(:users, on_delete: :nilify_all)
    end

    create index(:users, [:managed_by_professional_id])
  end
end
