defmodule Mehungry.Storage.S3 do
  @moduledoc """
  `Mehungry.Storage.Behaviour` over the legacy AWS S3 path (`Mehungry.S3` +
  ExAws). This keeps `STORAGE_BACKEND=s3` fully working through the unified
  `Mehungry.Storage` facade so the Supabase cutover (and any rollback) is a
  single config flip rather than a code change.

  Direct browser uploads are not issued here — the S3 era used sigv4 POST-policy
  forms (`MehungryWeb.SimpleS3Upload`); `signed_upload/2` is therefore
  unsupported under this backend.
  """

  @behaviour Mehungry.Storage.Behaviour

  @region "eu-central-1"

  @impl true
  def put(key, binary, opts) do
    case Mehungry.S3.upload_binary(binary, bucket(), key, content_type: content_type(opts)) do
      {:ok, _} -> {:ok, %{key: key, url: public_url(key)}}
      {:error, reason} -> {:error, {:transport_error, reason}}
    end
  end

  @impl true
  def get(key) do
    case Mehungry.S3.download_file(bucket(), key) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, {:transport_error, reason}}
    end
  end

  @impl true
  def delete(key) do
    case Mehungry.S3.delete_object(bucket(), key, region: @region) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:transport_error, reason}}
    end
  end

  @impl true
  def list(prefix) do
    case Mehungry.S3.list_objects(bucket(), prefix) do
      {:ok, %{body: %{contents: contents}}} -> {:ok, contents}
      {:error, reason} -> {:error, {:transport_error, reason}}
    end
  end

  @impl true
  def public_url(key), do: "https://#{bucket()}.s3.#{@region}.amazonaws.com/#{key}"

  # The REST upload endpoint issues a presigned PUT (S3 supports this directly);
  # the LiveView direct-upload path uses the sigv4 POST policy instead
  # (`MehungryWeb.SimpleS3Upload`) and never calls here.
  @impl true
  def signed_upload(key, opts) do
    content_type = content_type(opts)

    case Mehungry.S3.presigned_url(bucket(), key, 3600, :put) do
      {:ok, url} ->
        {:ok,
         %{
           method: "PUT",
           url: url,
           headers: %{"Content-Type" => content_type},
           key: key,
           public_url: public_url(key)
         }}

      {:error, reason} ->
        {:error, {:transport_error, reason}}
    end
  end

  defp content_type(opts), do: Keyword.get(opts, :content_type, "application/octet-stream")

  defp bucket, do: Application.get_env(:mehungry_web, :aws_bucket)
end
