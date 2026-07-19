defmodule Mehungry.Social.Instagram.ClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.Social.Instagram.Client` (wired up via the
  `:instagram_client` config key in `config/test.exs`) so tests never hit the
  network.

  Tests control responses per callback through app config:

      Application.put_env(:mehungry, :instagram_stub,
        exchange_long_lived_token: fn _short -> {:ok, %{"access_token" => "long"}} end
      )
      on_exit(fn -> Application.delete_env(:mehungry, :instagram_stub) end)
  """

  @behaviour Mehungry.Social.Instagram.ClientBehaviour

  @impl true
  def exchange_long_lived_token(short_lived_token),
    do:
      call(:exchange_long_lived_token, [short_lived_token], {
        :ok,
        %{"access_token" => "stub-long-lived", "token_type" => "bearer", "expires_in" => 5_184_000}
      })

  @impl true
  def refresh_long_lived_token(access_token),
    do:
      call(:refresh_long_lived_token, [access_token], {
        :ok,
        %{"access_token" => "stub-refreshed", "token_type" => "bearer", "expires_in" => 5_184_000}
      })

  @impl true
  def create_media_container(user_id, access_token, image_url, caption),
    do:
      call(
        :create_media_container,
        [user_id, access_token, image_url, caption],
        {:ok, "stub-container-id"}
      )

  @impl true
  def publish_media_container(user_id, access_token, container_id),
    do:
      call(
        :publish_media_container,
        [user_id, access_token, container_id],
        {:ok, "stub-media-id"}
      )

  defp call(fun_name, args, default) do
    case Application.get_env(:mehungry, :instagram_stub, [])[fun_name] do
      nil -> default
      fun -> apply(fun, args)
    end
  end
end
