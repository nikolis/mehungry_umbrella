defmodule Mehungry.Professionals.CalendarBusy do
  @moduledoc """
  A cached busy interval imported from a nutritionist's Google Calendar.

  The slot engine subtracts these from the bookable slots so the public booking
  page respects the nutritionist's personal calendar without a live Google call.
  Rows are replaced wholesale per professional by `GoogleCalendarBusyImportWorker`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "professional_calendar_busy" do
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime

    belongs_to :professional, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(busy, attrs) do
    busy
    |> cast(attrs, [:professional_id, :starts_at, :ends_at])
    |> validate_required([:professional_id, :starts_at, :ends_at])
    |> foreign_key_constraint(:professional_id)
  end
end
