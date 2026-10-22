defmodule MehungryWeb.Api.NotificationDispatcher do
  @moduledoc """
  Web implementation of `Mehungry.Notifications.Dispatcher` (wired via the
  `:notification_dispatcher` config key). Delivers a persisted notification to
  the mobile `user:<id>` channel and, when the recipient isn't connected, an
  Expo OS push — the same §4 payload both ways.

  Called from the core `Notifications.emit/3` seam, so it must tolerate running
  where the web endpoint isn't started (core-only tests): it no-ops in that case,
  leaving the already-persisted row as the record.
  """
  @behaviour Mehungry.Notifications.Dispatcher

  alias Mehungry.Repo
  alias MehungryWeb.Api.PushDispatch
  alias MehungryWeb.Api.V1.NotificationJSON
  alias MehungryWeb.Endpoint

  @impl true
  def deliver(notification) do
    if Process.whereis(Endpoint) do
      payload =
        notification
        |> Repo.preload(:actor)
        |> NotificationJSON.render()

      Endpoint.broadcast("user:#{notification.recipient_id}", "notification", payload)
      PushDispatch.enqueue(notification.recipient_id, payload)
    end

    :ok
  end
end
