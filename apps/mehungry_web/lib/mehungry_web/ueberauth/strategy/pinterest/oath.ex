defmodule Ueberauth.Strategy.Pinterest.OAuth do
  @moduledoc """
  OAuth2 client for Pinterest v5.

  config :ueberauth, Ueberauth.Strategy.Pinterest.OAuth,
    client_id: System.get_env("PINTEREST_CLIENT_ID"),
    client_secret: System.get_env("PINTEREST_CLIENT_SECRET")
  """
  use OAuth2.Strategy

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Pinterest.OAuth, [])

    opts =
      defaults()
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    OAuth2.Client.new(opts)
  end

  # Token exchange must hit the same environment as Mehungry.Social.Pinterest:
  # sandbox and production tokens are not interchangeable, so both derive their
  # host from the :pinterest_api_base config key (production by default).
  # Accounts must be reconnected after switching environments.
  defp defaults do
    api_base =
      Application.get_env(:mehungry, :pinterest_api_base, "https://api.pinterest.com/v5")

    [
      strategy: __MODULE__,
      site: String.replace_suffix(api_base, "/v5", ""),
      authorize_url: "https://www.pinterest.com/oauth/",
      token_url: api_base <> "/oauth/token"
    ]
  end

  def authorize_url!(params \\ [], opts \\ []) do
    opts |> client() |> OAuth2.Client.authorize_url!(params)
  end

  def get_token!(params \\ [], opts \\ []) do
    opts |> client() |> OAuth2.Client.get_token!(params)
  end

  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  # Pinterest v5 token endpoint requires HTTP Basic auth
  # (base64(client_id:client_secret)) rather than client_secret in the body.
  def get_token(client, params, headers) do
    credentials = Base.encode64("#{client.client_id}:#{client.client_secret}")

    client
    |> put_header("Authorization", "Basic #{credentials}")
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
