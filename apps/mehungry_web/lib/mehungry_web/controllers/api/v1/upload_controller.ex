defmodule MehungryWeb.Api.V1.UploadController do
  @moduledoc """
  Media upload for recipe/avatar images (spec §11). Two flows:

    * presigned PUT (preferred) — the client PUTs the binary straight to S3, then
      passes the returned `upload_id` (object key) to the create/update body.
    * direct multipart (fallback) — the server streams the file to S3.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Storage

  action_fallback MehungryWeb.Api.V1.FallbackController

  @valid_kinds ~w(recipe_image avatar)

  def presign(conn, params) do
    kind = params["kind"] || "recipe_image"
    content_type = params["content_type"] || "image/jpeg"

    with :ok <- validate_kind(kind),
         :ok <- ensure_configured(),
         key <- object_key(kind, content_type),
         {:ok, upload} <- Storage.signed_upload(key, content_type: content_type) do
      json(
        conn,
        data(%{
          upload_id: upload.key,
          url: upload.url,
          method: upload.method,
          headers: Map.put(upload.headers, "Content-Type", content_type)
        })
      )
    end
  end

  def create(conn, %{"file" => %Plug.Upload{} = upload} = params) do
    kind = params["kind"] || "recipe_image"
    content_type = upload.content_type || "image/jpeg"

    with :ok <- validate_kind(kind),
         :ok <- ensure_configured(),
         key <- object_key(kind, content_type),
         {:ok, %{url: url, key: key}} <-
           Storage.put_file(key, upload.path, content_type: content_type) do
      json(conn, data(%{upload_id: key, url: url}))
    end
  end

  def create(conn, _params), do: {:error, :bad_request}

  # ── helpers ────────────────────────────────────────────────────────────

  defp validate_kind(kind) when kind in @valid_kinds, do: :ok
  defp validate_kind(_), do: {:error, :bad_request}

  defp ensure_configured do
    if Storage.configured?(), do: :ok, else: {:error, "uploads not configured"}
  end

  defp object_key(kind, content_type) do
    prefix = if kind == "avatar", do: "avatars/tmp", else: "recipe_images/tmp"
    "#{prefix}/#{Ecto.UUID.generate()}#{extension(content_type)}"
  end

  defp extension("image/png"), do: ".png"
  defp extension("image/webp"), do: ".webp"
  defp extension(_), do: ".jpg"
end
