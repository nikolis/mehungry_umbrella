defmodule Mehungry.Social.Instagram do
  @moduledoc """
  Instagram integration context: OAuth token lifecycle (exchange, refresh,
  staleness) and media publishing for both bot and regular users.

  The HTTP layer is behind `Mehungry.Social.Instagram.ClientBehaviour`, resolved via
  the `:instagram_client` app config key so tests can stub it.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Accounts
  alias Mehungry.Accounts.User
  alias Mehungry.Social.Instagram.{Caption, Token}
  alias Mehungry.Repo

  @doc """
  Exchanges a short-lived OAuth token for a long-lived one and stores it on the
  user. On failure nothing is saved and the error is returned, so a broken
  exchange can never masquerade as a connected account.
  """
  def connect_account(%User{} = user, short_lived_token, instagram_user_id) do
    case client().exchange_long_lived_token(short_lived_token) do
      {:ok, %{"access_token" => _} = response} ->
        token = Token.build(response, instagram_user_id)
        Accounts.update_user_tokens(user, %{"instagram_token" => token})

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the user's long-lived token. On a 4xx that indicates an
  expired/invalid token the stored token is marked stale (so publishing
  short-circuits and the admin UI asks for a reconnect); transient errors leave
  the stored token untouched.
  """
  def refresh_user_token(%User{} = user) do
    token = user.instagram_token || %{}

    case client().refresh_long_lived_token(token["access_token"]) do
      {:ok, %{"access_token" => _} = response} ->
        refreshed =
          response
          |> Token.build(token["user_id"])
          |> Map.put(
            "obtained_at",
            token["obtained_at"] || DateTime.to_iso8601(DateTime.utc_now())
          )

        Accounts.update_user_tokens(user, %{"instagram_token" => refreshed})

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, {:http_error, status, body} = reason} when status in 400..499 ->
        if invalid_token_error?(body) do
          mark_stale(user, reason)
        end

        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Posts a recipe image + caption to the user's Instagram account.
  Returns `{:ok, %{media_id: id}}` or a typed error.
  """
  def post_recipe(%User{} = user, recipe) do
    token = user.instagram_token || %{}

    case Token.status(token) do
      :not_connected ->
        {:error, :not_connected}

      status when status in [:stale, :error] ->
        {:error, :token_stale}

      _connected ->
        user_id = to_string(token["user_id"] || "")
        access_token = token["access_token"]
        caption = Caption.build(recipe)

        with {:ok, container_id} <-
               client().create_media_container(user_id, access_token, recipe.image_url, caption),
             {:ok, media_id} <-
               client().publish_media_container(user_id, access_token, container_id) do
          {:ok, %{media_id: media_id}}
        end
    end
  end

  @doc """
  Token status for a user or raw token map — see `Mehungry.Social.Instagram.Token.status/1`.
  """
  def token_status(%User{instagram_token: token}), do: Token.status(token)
  def token_status(token), do: Token.status(token)

  @doc """
  Users with a stored Instagram access token (legacy or current shape).
  Corrupted error-map tokens lack the key and are excluded.
  """
  def list_users_with_tokens do
    User
    |> where([u], fragment("? \\? ?", u.instagram_token, "access_token"))
    |> Repo.all()
  end

  @doc """
  Marks the stored token stale so publishing short-circuits and the admin UI
  shows a reconnect prompt.
  """
  def mark_stale(%User{} = user, reason) do
    token =
      (user.instagram_token || %{})
      |> Map.put("status", "stale")
      |> Map.put("last_refresh_error", format_reason(reason))

    Accounts.update_user_tokens(user, %{"instagram_token" => token})
  end

  defp invalid_token_error?(body) when is_map(body) do
    error = body["error"] || %{}
    message = String.downcase(to_string(error["message"] || ""))

    error["code"] == 190 or error["type"] == "OAuthException" or
      String.contains?(message, ["expired", "invalid"])
  end

  defp invalid_token_error?(_body), do: false

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp client do
    Application.get_env(:mehungry, :instagram_client, Mehungry.Social.Instagram.Client)
  end
end
