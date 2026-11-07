defmodule MehungryWeb.Api.V1.UploadController do
  @moduledoc """
  Media upload for recipe/avatar images (spec §11). Two flows:

    * presigned PUT (preferred) — the client PUTs the binary straight to S3, then
      passes the returned `upload_id` (object key) to the create/update body.
    * direct multipart (fallback) — the server streams the file to S3.

  `kind: "progress_photo"` targets the **private** bucket (sensitive body
  photos, §19) — those responses carry `url: null` and the object is readable
  only via the signed URLs the §19 endpoints serve.
  """
  use MehungryWeb, :controller

  require Logger

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Storage

  action_fallback MehungryWeb.Api.V1.FallbackController

  @valid_kinds ~w(recipe_image avatar progress_photo)

  def presign(conn, params) do
    kind = params["kind"] || "recipe_image"
    content_type = params["content_type"] || "image/jpeg"

    with :ok <- validate_kind(kind),
         :ok <- ensure_configured(),
         key <- object_key(kind, content_type),
         {:ok, upload} <- signed_upload(key, content_type, kind) do
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
         {:ok, binary} <- read_upload(upload),
         {:ok, %{url: url, key: key}} <- put_object(key, binary, content_type, kind) do
      json(conn, data(%{upload_id: key, url: url}))
    end
  end

  def create(conn, _params), do: {:error, :bad_request}

  # ── helpers ────────────────────────────────────────────────────────────

  # Storage backends return `{:error, {:http_error, _, _}}` /
  # `{:error, {:transport_error, _}}` on upstream failure. Collapse those to the
  # `:upstream_error` the fallback controller maps to a clean 502 — a raw tuple
  # would otherwise match no fallback clause and crash into a 500.
  defp signed_upload(key, content_type, kind) do
    case Storage.signed_upload(key, [content_type: content_type] ++ bucket_opts(kind)) do
      {:ok, upload} ->
        {:ok, upload}

      {:error, reason} ->
        Logger.error("Upload presign failed for #{key}: #{inspect(reason)}")
        {:error, :upstream_error}
    end
  end

  # Read the multipart temp file without raising — the file may be gone or
  # unreadable, and `File.read!/1` would crash into a 500.
  defp read_upload(%Plug.Upload{path: path}) do
    case File.read(path) do
      {:ok, binary} ->
        {:ok, binary}

      {:error, reason} ->
        Logger.error("Upload temp file unreadable (#{inspect(reason)}): #{inspect(path)}")
        {:error, :upstream_error}
    end
  end

  defp put_object(key, binary, content_type, kind) do
    case Storage.put(key, binary, [content_type: content_type] ++ bucket_opts(kind)) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Upload store failed for #{key}: #{inspect(reason)}")
        {:error, :upstream_error}
    end
  end

  # Progress photos are sensitive media (body photos) — they go to the private
  # bucket and are only ever read back through short-lived signed URLs (§19);
  # their presign/response `url` fields carry no public object URL.
  defp bucket_opts("progress_photo"), do: [bucket: :private]
  defp bucket_opts(_), do: []

  defp validate_kind(kind) when kind in @valid_kinds, do: :ok
  defp validate_kind(_), do: {:error, :bad_request}

  defp ensure_configured do
    if Storage.configured?(), do: :ok, else: {:error, "uploads not configured"}
  end

  defp object_key(kind, content_type) do
    prefix =
      case kind do
        "avatar" -> "avatars/tmp"
        "progress_photo" -> "progress_photos"
        _ -> "recipe_images/tmp"
      end

    "#{prefix}/#{Ecto.UUID.generate()}#{extension(content_type)}"
  end

  defp extension("image/png"), do: ".png"
  defp extension("image/webp"), do: ".webp"
  defp extension(_), do: ".jpg"
end
