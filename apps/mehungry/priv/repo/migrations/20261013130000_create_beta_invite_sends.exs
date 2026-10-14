defmodule Mehungry.Repo.Migrations.CreateBetaInviteSends do
  use Ecto.Migration

  def change do
    create table(:beta_invite_sends) do
      add :email, :string, null: false
      add :canonical_email, :string, null: false
      add :version, :string, null: false
      add :status, :string, null: false, default: "ok"
      add :beta_signup_id, references(:beta_signups, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    # One row per (tester, version): resending the same build is idempotent.
    create unique_index(:beta_invite_sends, [:canonical_email, :version])
    create index(:beta_invite_sends, [:beta_signup_id])
    create index(:beta_invite_sends, [:version])
  end
end
