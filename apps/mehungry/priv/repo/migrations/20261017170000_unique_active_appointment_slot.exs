defmodule Mehungry.Repo.Migrations.UniqueActiveAppointmentSlot do
  use Ecto.Migration

  # Closes the booking double-book race: two concurrent `request_appointment/4`
  # calls could both pass the `slot_open?` SELECT and both insert. A partial
  # unique index makes the DB the final arbiter — only one *active*
  # (requested/accepted) appointment can hold a given (professional, time).
  # Declined/cancelled rows are excluded so a freed slot can be rebooked.
  def change do
    create unique_index(
             :professional_appointments,
             [:professional_id, :scheduled_at],
             where: "status in ('requested', 'accepted')",
             name: :professional_appointments_active_slot_unique
           )
  end
end
