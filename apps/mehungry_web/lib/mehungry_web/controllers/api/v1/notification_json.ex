defmodule MehungryWeb.Api.V1.NotificationJSON do
  @moduledoc """
  Serializer for the notification contract shared by the REST inbox, the
  `user:<id>` channel, and (Phase 2) OS push (spec §13, `docs/notifications_system.md` §4).

  `render/1` expects a `%Mehungry.Notifications.Notification{}` with its `:actor`
  association loaded (or set to the known actor struct / nil).
  """

  import MehungryWeb.Api.V1.JSON.Helpers

  @doc "The §4 notification object (not wrapped)."
  def render(notification) do
    %{
      id: notification.id,
      type: notification.type,
      actor: actor(notification.actor),
      subject: subject(notification.subject_type, notification.subject_id),
      data: notification.data || %{},
      read: not is_nil(notification.read_at),
      inserted_at: utc(notification.inserted_at)
    }
  end

  defp actor(%Ecto.Association.NotLoaded{}), do: nil
  defp actor(nil), do: nil

  defp actor(user) do
    %{id: user.id, alias: user.name || user.email, avatar_url: user.profile_pic}
  end

  defp subject(nil, _id), do: nil
  defp subject(_type, nil), do: nil
  defp subject(type, id), do: %{type: type, id: id}
end
