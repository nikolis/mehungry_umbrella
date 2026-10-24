defmodule Mehungry.Notifications.NoopDispatcher do
  @moduledoc """
  Default `Mehungry.Notifications.Dispatcher` — does nothing. Used by the core
  app and core-only tests, where persistence is the only concern and there's no
  web layer to broadcast through. The web app overrides it via
  `:notification_dispatcher` config.
  """
  @behaviour Mehungry.Notifications.Dispatcher

  @impl true
  def deliver(_notification), do: :ok
end
