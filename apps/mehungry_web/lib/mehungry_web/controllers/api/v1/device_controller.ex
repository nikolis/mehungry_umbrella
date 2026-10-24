defmodule MehungryWeb.Api.V1.DeviceController do
  @moduledoc """
  Device registration for OS push (spec §5.1). The mobile client registers its
  Expo push token after login and removes it on logout. Backed by
  `Mehungry.Notifications` device functions.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Notifications

  action_fallback MehungryWeb.Api.V1.FallbackController

  @doc "POST /me/devices — register/refresh this device's Expo push token."
  def create(conn, %{"expo_token" => token, "platform" => platform}) do
    with {:ok, _device} <- Notifications.register_device(uid(conn), token, platform) do
      conn |> put_status(:created) |> json(data(%{ok: true}))
    end
  end

  @doc "DELETE /me/devices/:token — remove this device's token (logout)."
  def delete(conn, %{"token" => token}) do
    :ok = Notifications.delete_device(uid(conn), token)
    send_resp(conn, :no_content, "")
  end

  defp uid(conn), do: conn.assigns.current_user.id
end
