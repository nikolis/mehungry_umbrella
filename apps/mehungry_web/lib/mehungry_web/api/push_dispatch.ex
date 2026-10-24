defmodule MehungryWeb.Api.PushDispatch do
  @moduledoc """
  OS push delivery (Expo), called by `MehungryWeb.Api.NotificationDispatcher`
  after a notification is persisted + live-broadcast. Enqueues
  `Mehungry.ObanWorkers.PushNotificationWorker` to fan the notification out to
  the recipient's registered devices.

  **Presence-gated**: if the recipient currently has a live `user:<id>` socket
  (tracked by `MehungryWeb.UserChannel`), they already received the live
  broadcast, so we skip the push entirely. See `docs/notifications_system.md` §7.
  """

  alias Mehungry.ObanWorkers.PushNotificationWorker
  alias MehungryWeb.Presence

  @doc """
  Queue an OS push for `recipient_id` carrying the §4 notification `payload`,
  unless the recipient is connected. Always returns `:ok` — never raises into
  the request path.
  """
  @spec enqueue(integer(), map()) :: :ok
  def enqueue(recipient_id, payload) do
    unless connected?(recipient_id) do
      PushNotificationWorker.enqueue(recipient_id, payload)
    end

    :ok
  end

  defp connected?(recipient_id) do
    Presence.list("user:#{recipient_id}") != %{}
  end
end
