defmodule Mehungry.Repo.Migrations.CreateProfessionalServices do
  use Ecto.Migration

  def change do
    create table(:professional_services) do
      # Keyed on the nutritionist's user id, matching professional_appointments.
      add :professional_id, references(:users, on_delete: :delete_all), null: false

      # "intro" | "session" | "package"
      add :kind, :string, null: false, default: "session"
      add :name, :string, null: false
      add :description, :text

      # Money in cents (matches the existing consultation_fee_cents convention).
      add :price_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "eur"

      add :duration_minutes, :integer
      # Packages bundle several sessions; a plain session is 1.
      add :session_count, :integer, null: false, default: 1

      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps()
    end

    create index(:professional_services, [:professional_id])

    # The free 15-min intro is a reserved, system-managed row — a nutritionist
    # may have at most one. Guarantees the "every nutritionist offers a free
    # intro" obligation structurally.
    create unique_index(:professional_services, [:professional_id],
             where: "kind = 'intro'",
             name: :professional_services_one_intro
           )

    # Link an appointment to the service it was booked for (nullable: legacy
    # free-request appointments predate services; new bookings set it).
    alter table(:professional_appointments) do
      add :professional_service_id,
          references(:professional_services, on_delete: :nilify_all)
    end

    create index(:professional_appointments, [:professional_service_id])
  end
end
