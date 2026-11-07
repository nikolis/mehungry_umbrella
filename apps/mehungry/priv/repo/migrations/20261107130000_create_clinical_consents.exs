defmodule Mehungry.Repo.Migrations.CreateClinicalConsents do
  use Ecto.Migration

  # GDPR Art. 9 explicit-consent audit trail for processing a client's
  # special-category health data (onboarding answers + body measurements) in the
  # nutritionist relationship. Append-only: a withdrawal stamps `withdrawn_at`
  # rather than deleting the row, so the history of grants/withdrawals survives.
  def change do
    create table(:clinical_consents) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :withdrawn_at, :naive_datetime

      timestamps()
    end

    create index(:clinical_consents, [:user_id])
  end
end
