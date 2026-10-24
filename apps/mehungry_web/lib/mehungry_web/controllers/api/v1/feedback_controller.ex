defmodule MehungryWeb.Api.V1.FeedbackController do
  @moduledoc """
  App feedback submission (spec §17) — the mobile mirror of the `/feedback`
  LiveView (`MehungryWeb.FeedbackLive`). Public endpoint with optional auth:
  when a bearer token is present the feedback is attributed to the caller
  (`user_id` + their account `email`, exactly as the LiveView does on submit);
  anonymous callers may supply an optional `email` for a reply.

  Reuses `Mehungry.Feedback.create_feedback/1` — the same domain function the
  LiveView calls — so validation (message 10–2000 chars, email format) stays in
  one place.
  """
  use MehungryWeb, :controller

  alias Mehungry.Feedback
  alias MehungryWeb.Api.V1.FeedbackJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def create(conn, params) do
    user = conn.assigns[:current_user]

    attrs =
      params
      |> Map.take(["message", "email"])
      |> maybe_attribute(user)

    with {:ok, feedback} <- Feedback.create_feedback(attrs) do
      conn
      |> put_status(:created)
      |> json(FeedbackJSON.show(%{feedback: feedback}))
    end
  end

  # Logged-in: attach the account and override email with the account email —
  # mirrors FeedbackLive.handle_event("submit", …).
  defp maybe_attribute(attrs, nil), do: attrs

  defp maybe_attribute(attrs, user) do
    Map.merge(attrs, %{"user_id" => user.id, "email" => user.email})
  end
end
