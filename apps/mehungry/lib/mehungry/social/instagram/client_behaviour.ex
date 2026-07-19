defmodule Mehungry.Social.Instagram.ClientBehaviour do
  @moduledoc """
  Contract for the Instagram Graph API client, so tests can swap in a stub via
  the `:instagram_client` app config key (same pattern as `:off_client`).
  """

  @type api_error ::
          {:http_error, status :: non_neg_integer(), body :: map() | String.t()}
          | {:transport_error, term()}

  @callback exchange_long_lived_token(short_lived_token :: String.t()) ::
              {:ok, map()} | {:error, api_error()}

  @callback refresh_long_lived_token(access_token :: String.t()) ::
              {:ok, map()} | {:error, api_error()}

  @callback create_media_container(
              user_id :: String.t(),
              access_token :: String.t(),
              image_url :: String.t(),
              caption :: String.t()
            ) :: {:ok, container_id :: String.t()} | {:error, api_error()}

  @callback publish_media_container(
              user_id :: String.t(),
              access_token :: String.t(),
              container_id :: String.t()
            ) :: {:ok, media_id :: String.t()} | {:error, api_error()}
end
