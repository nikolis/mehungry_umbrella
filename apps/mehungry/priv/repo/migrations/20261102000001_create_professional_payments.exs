defmodule Mehungry.Repo.Migrations.CreateProfessionalPayments do
  use Ecto.Migration

  def change do
    create table(:professional_payments) do
      add :appointment_id,
          references(:professional_appointments, on_delete: :delete_all),
          null: false

      # Denormalized for earnings queries / support lookups.
      add :professional_id, references(:users, on_delete: :nilify_all)
      add :client_id, references(:users, on_delete: :nilify_all)

      # Which service/package was booked (snapshot of the priced offering).
      add :professional_service_id,
          references(:professional_services, on_delete: :nilify_all)

      # Stripe object ids.
      add :stripe_checkout_session_id, :string
      add :stripe_payment_intent_id, :string
      add :stripe_charge_id, :string
      add :stripe_account_id, :string

      # Money snapshot at booking time (immutable record of what was agreed).
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false
      # Our flat 5% commission — VAT-INCLUSIVE; fee_vat_cents is the VAT slice
      # contained within it (0 for reverse-charge accounts).
      add :platform_fee_cents, :integer, null: false
      add :fee_vat_cents, :integer, default: 0, null: false
      add :refunded_amount_cents, :integer, default: 0, null: false

      # pending → authorized → paid → refunded/partially_refunded; disputed/canceled/failed.
      add :status, :string, default: "pending", null: false

      add :authorized_at, :naive_datetime
      add :captured_at, :naive_datetime
      add :canceled_at, :naive_datetime
      add :refunded_at, :naive_datetime
      add :disputed_at, :naive_datetime

      add :failure_reason, :string

      timestamps()
    end

    create unique_index(:professional_payments, [:appointment_id])
    create unique_index(:professional_payments, [:stripe_payment_intent_id])
    create index(:professional_payments, [:stripe_checkout_session_id])
    create index(:professional_payments, [:professional_id])
    create index(:professional_payments, [:status])
  end
end
