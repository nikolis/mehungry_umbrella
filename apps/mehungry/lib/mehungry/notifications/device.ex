defmodule Mehungry.Notifications.Device do
  @moduledoc """
  A registered mobile device for OS push (Expo). One row per Expo push token;
  the token belongs to exactly one user at a time (shared hardware re-registers
  and moves). `last_seen_at` is bumped on each registration.

  See `docs/notifications_system.md` §7.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Accounts.User

  @platforms ~w(ios android web)

  schema "user_devices" do
    field :expo_token, :string
    field :platform, :string
    field :last_seen_at, :utc_datetime

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:user_id, :expo_token, :platform, :last_seen_at])
    |> validate_required([:user_id, :expo_token, :platform])
    |> validate_inclusion(:platform, @platforms)
    |> unique_constraint(:expo_token)
  end
end
