defmodule Mehungry.Repo.Migrations.CreateProfessionalGoogleAccounts do
  use Ecto.Migration

  def change do
    create table(:professional_google_accounts) do
      # One connected Google Calendar per nutritionist.
      add :professional_id, references(:users, on_delete: :delete_all), null: false

      # OAuth tokens. Stored plaintext to match the app's existing provider-token
      # practice (users.instagram_token/facebook_token/pinterest_token jsonb) —
      # encryption is a tracked follow-up.
      add :access_token, :text
      add :refresh_token, :text
      add :token_expires_at, :utc_datetime
      add :scope, :text

      # Which calendar to write events to / read busy from.
      add :calendar_id, :string, default: "primary", null: false

      add :connected_at, :utc_datetime
      # Busy-import bookkeeping.
      add :busy_synced_at, :utc_datetime
      add :sync_token, :text

      timestamps()
    end

    create unique_index(:professional_google_accounts, [:professional_id])
  end
end
