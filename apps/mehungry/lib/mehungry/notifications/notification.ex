defmodule Mehungry.Notifications.Notification do
  @moduledoc """
  A single activity notification shown to `recipient` — e.g. "someone commented
  on your recipe" or "someone started following you".

  `actor` is who caused it (nil for system/AI events). `subject_type`/`subject_id`
  name the thing the notification points at and drive the mobile deep-link
  (`recipe` → recipe detail, `user` → that user's profile). `data` holds
  denormalized render bits (recipe title, comment preview) so the inbox needs no
  extra joins. `read_at` is nil until the recipient opens the inbox.

  See `docs/notifications_system.md`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Accounts.User

  @types ~w(follow comment comment_answer ai_ready invitation)

  schema "notifications" do
    field :type, :string
    field :subject_type, :string
    field :subject_id, :integer
    field :data, :map, default: %{}
    field :read_at, :utc_datetime

    belongs_to :recipient, User
    belongs_to :actor, User

    timestamps()
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:recipient_id, :actor_id, :type, :subject_type, :subject_id, :data, :read_at])
    |> validate_required([:recipient_id, :type])
    |> validate_inclusion(:type, @types)
  end
end
