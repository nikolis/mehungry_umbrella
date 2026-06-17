defmodule MehungryWeb.BotOAuthController do
  @moduledoc """
  Stores the bot user ID in session before redirecting to the OAuth provider.
  AuthController's callback reads "oauth_target_user_id" to save the token
  to the bot user instead of the logged-in admin.
  """

  use MehungryWeb, :controller

  def set_target(conn, %{"bot_user_id" => bot_user_id, "provider" => provider}) do
    conn
    |> put_session("oauth_target_user_id", bot_user_id)
    |> redirect(to: "/auth/#{provider}")
  end
end
