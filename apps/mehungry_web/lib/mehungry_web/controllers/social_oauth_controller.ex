defmodule MehungryWeb.SocialOAuthController do
  @moduledoc """
  Entry point for *connecting* a social account (as opposed to logging in with
  one). It records an explicit `oauth_intent` in the session before redirecting
  into the shared `/auth/:provider` request route, so `AuthController.callback`
  knows this round-trip is a connect — and for whom — instead of inferring it
  from "is someone logged in?".

  The session marker is a single map `%{"action" => "connect", "target" => id}`.
  Writing it fresh on every connect (last-write-wins) is what prevents an
  abandoned bot-connect from later binding a token to the wrong user. The
  callback additionally authorizes the target (you may connect your own account;
  only an admin may connect a managed bot user's account).
  """

  use MehungryWeb, :controller

  # Facebook Page-publishing scopes, requested ONLY on connect — kept out of the
  # login flow (config default scope) so plain login never asks for them.
  @facebook_connect_scope "public_profile,email,pages_manage_engagement,pages_manage_posts,pages_read_engagement"

  @doc "Connect the logged-in user's own social account (profile page)."
  def connect(conn, %{"provider" => provider}) do
    start_connect(conn, provider, conn.assigns.current_user.id)
  end

  @doc "Connect a managed bot user's social account (admin AI-bot social page)."
  def set_target(conn, %{"bot_user_id" => bot_user_id, "provider" => provider}) do
    start_connect(conn, provider, bot_user_id)
  end

  defp start_connect(conn, provider, target_id) do
    conn
    |> put_session("oauth_intent", %{"action" => "connect", "target" => to_string(target_id)})
    |> redirect(to: request_path(provider))
  end

  defp request_path("facebook"), do: "/auth/facebook?scope=#{@facebook_connect_scope}"
  defp request_path(provider), do: "/auth/#{provider}"
end
