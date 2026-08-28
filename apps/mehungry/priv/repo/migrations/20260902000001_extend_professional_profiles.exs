defmodule Mehungry.Repo.Migrations.ExtendProfessionalProfiles do
  use Ecto.Migration

  def change do
    alter table(:professional_profiles) do
      # Identity / public
      add :display_name, :string
      add :slug, :string
      add :photo_url, :string
      add :is_public, :boolean, null: false, default: false

      # Details
      add :education, :text
      add :scientific_contributions, :text
      add :professional_achievements, :text

      # Contact / location
      add :city, :string
      add :region, :string
      add :office_address, :string
      add :phone, :string
      add :contact_email, :string
      add :website_url, :string
      add :timezone, :string

      # Scheduling
      add :appointment_slot_minutes, :integer, null: false, default: 60

      # Payments (Stripe Connect — minimal slice)
      add :consultation_fee_cents, :integer
      add :stripe_connect_account_id, :string
      add :stripe_charges_enabled, :boolean, null: false, default: false
    end

    create unique_index(:professional_profiles, [:slug])
    create index(:professional_profiles, [:city])
    create index(:professional_profiles, [:is_public, :city])
  end
end
