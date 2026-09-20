defmodule Mehungry.Repo.Migrations.RequireProfessionalClientUser do
  use Ecto.Migration

  @moduledoc """
  Enforces the "a client record is never headless" invariant: every
  `professional_clients` row must reference a platform `user_id`.

  Existing headless records (imported/authored before this rule) are deleted
  outright — their `client_intakes` and `consultation_notes` cascade away via
  their `on_delete: :delete_all` foreign keys. The `user_id` FK itself is
  switched from `nilify_all` to `delete_all` so it can be `NOT NULL`.
  """

  def up do
    execute("DELETE FROM professional_clients WHERE user_id IS NULL")

    drop constraint(:professional_clients, "professional_clients_user_id_fkey")

    alter table(:professional_clients) do
      modify :user_id, references(:users, on_delete: :delete_all), null: false
    end
  end

  def down do
    drop constraint(:professional_clients, "professional_clients_user_id_fkey")

    alter table(:professional_clients) do
      modify :user_id, references(:users, on_delete: :nilify_all), null: true
    end
  end
end
