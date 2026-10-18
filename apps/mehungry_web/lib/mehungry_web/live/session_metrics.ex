defmodule MehungryWeb.SessionMetrics do
  @moduledoc """
  `on_mount` hook that records anonymous, consent-independent session metrics.

  On the *connected* mount it registers the LiveView process with
  `Mehungry.Meta.SessionAggregator`, which times the process lifetime and folds
  it into a daily aggregate counter when the process dies. Unlike the
  consent-gated Visit tracking in `MehungryWeb.Presence`, this has **no**
  `cookie_consent` check — it measures 100% of traffic — which is safe precisely
  because nothing personal is ever stored (see `Mehungry.Meta.DailySessionMetric`).

  Gated on `connected?/1` so the dead HTTP mount is not counted.
  """
  import Phoenix.LiveView, only: [connected?: 1]

  alias Mehungry.Meta.SessionAggregator

  def on_mount(_name, _params, _session, socket) do
    if connected?(socket), do: SessionAggregator.track()
    {:cont, socket}
  end
end
