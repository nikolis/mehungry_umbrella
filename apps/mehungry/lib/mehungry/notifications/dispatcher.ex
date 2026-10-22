defmodule Mehungry.Notifications.Dispatcher do
  @moduledoc """
  Seam for delivering a persisted notification to the outside world (the mobile
  `user:<id>` channel + OS push). Lets the web-agnostic `Mehungry.Notifications`
  context fire a notification from *any* caller (LiveView, REST, channel) without
  depending on the web layer.

  The real implementation (`MehungryWeb.Api.NotificationDispatcher`) is wired via
  the `:notification_dispatcher` app config key; `NoopDispatcher` is the default
  so the core app (and core-only tests) stay free of web dependencies.
  """

  @callback deliver(notification :: struct()) :: any()
end
