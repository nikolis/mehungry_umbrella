defmodule MehungryWeb.SessionMetrics do
  @moduledoc """
  `on_mount` hook that records anonymous, consent-independent **visit** metrics.

  On the *connected* mount it registers the LiveView process with
  `Mehungry.Meta.SessionAggregator`, keyed by the per-tab `visit_token` the
  client sends as a connect param, so every page in a visit folds into one record
  instead of fragmenting per LiveView process. The visitor's User-Agent (read
  from the socket connect info, never stored) lets the aggregator drop known
  bots. It also attaches a `handle_event` hook so the first genuine client
  interaction (`"mh:visit_engaged"`, pushed by the `VisitEngagement` JS hook)
  marks the visit engaged — the aggregator only counts visits that are engaged,
  lasted >=10s, or spanned >=2 views.

  Unlike the consent-gated Visit tracking in `MehungryWeb.Presence`, this has
  **no** `cookie_consent` check — it measures 100% of traffic — which is safe
  precisely because nothing personal is ever stored (see
  `Mehungry.Meta.DailySessionMetric`).

  Gated on `connected?/1` so the dead HTTP mount is not counted.
  """
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1, get_connect_info: 2, attach_hook: 4]

  alias Mehungry.Meta.SessionAggregator

  def on_mount(_name, _params, _session, socket) do
    if connected?(socket) do
      token = get_connect_params(socket)["visit_token"]
      user_agent = get_connect_info(socket, :user_agent)
      SessionAggregator.track(token, user_agent)

      socket = attach_hook(socket, :visit_engagement, :handle_event, &handle_engaged/3)
      {:cont, socket}
    else
      {:cont, socket}
    end
  end

  # The VisitEngagement JS hook pushes this on the first real interaction. We
  # intercept it centrally here (so no LiveView needs its own handler) and halt.
  defp handle_engaged("mh:visit_engaged", _params, socket) do
    SessionAggregator.engaged()
    {:halt, socket}
  end

  defp handle_engaged(_event, _params, socket), do: {:cont, socket}
end
