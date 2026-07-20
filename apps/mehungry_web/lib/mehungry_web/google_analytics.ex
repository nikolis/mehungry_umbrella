defmodule MehungryWeb.GoogleAnalytics do
  @moduledoc """
  Fires GA4 custom events from LiveViews via `push_event/3`. The client-side
  `phx:ga_event` listener (assets/js/app.js) forwards these to `gtag`, which
  applies Consent Mode automatically (cookieless ping pre-consent, full event
  post-consent) — no consent state needs to be threaded through the socket.
  """

  @spec track(Phoenix.LiveView.Socket.t(), String.t(), map()) :: Phoenix.LiveView.Socket.t()
  def track(socket, event_name, params \\ %{}) do
    Phoenix.LiveView.push_event(socket, "ga_event", %{name: event_name, params: params})
  end
end
