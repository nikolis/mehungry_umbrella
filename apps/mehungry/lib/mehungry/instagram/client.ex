defmodule Mehungry.Instagram.Client do
  @moduledoc """
  HTTP client for the Instagram Graph API (Instagram Business Login tokens).
  All calls return `{:ok, decoded_body}` (or the extracted id for media calls)
  or `{:error, {:http_error, status, body} | {:transport_error, reason}}`.
  """

  @behaviour Mehungry.Instagram.ClientBehaviour

  require Logger

  @api_base "https://graph.instagram.com"
  @api_version "v21.0"

  @impl true
  def exchange_long_lived_token(short_lived_token) do
    get("/access_token", "exchange_long_lived_token", %{
      grant_type: "ig_exchange_token",
      client_secret: client_secret(),
      access_token: short_lived_token
    })
  end

  @impl true
  def refresh_long_lived_token(access_token) do
    get("/refresh_access_token", "refresh_long_lived_token", %{
      grant_type: "ig_refresh_token",
      access_token: access_token
    })
  end

  @impl true
  def create_media_container(user_id, access_token, image_url, caption) do
    with {:ok, body} <-
           post("/#{@api_version}/#{user_id}/media", "create_media_container", access_token, %{
             image_url: image_url,
             caption: caption,
             media_type: "IMAGE"
           }) do
      {:ok, body["id"]}
    end
  end

  @impl true
  def publish_media_container(user_id, access_token, container_id) do
    with {:ok, body} <-
           post(
             "/#{@api_version}/#{user_id}/media_publish",
             "publish_media_container",
             access_token,
             %{creation_id: container_id}
           ) do
      {:ok, body["id"]}
    end
  end

  defp get(path, op, params) do
    (@api_base <> path)
    |> HTTPoison.get([], params: params)
    |> handle_response(op)
  end

  defp post(path, op, access_token, params) do
    headers = [
      Authorization: "Bearer #{access_token}",
      Accept: "application/json; charset=utf-8"
    ]

    (@api_base <> path)
    |> HTTPoison.post("", headers, params: params)
    |> handle_response(op)
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}, op)
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _} ->
        Logger.error("[Instagram] #{op}: HTTP #{status} with undecodable body — #{inspect(body)}")
        {:error, {:http_error, status, body}}
    end
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}, op) do
    decoded =
      case Jason.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    Logger.error("[Instagram] #{op}: HTTP #{status} — #{inspect(decoded)}")
    {:error, {:http_error, status, decoded}}
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}, op) do
    Logger.error("[Instagram] #{op}: transport error — #{inspect(reason)}")
    {:error, {:transport_error, reason}}
  end

  defp client_secret do
    Application.get_env(:ueberauth, Ueberauth.Strategy.Instagram.OAuth)[:client_secret]
  end
end
