defmodule MehungryWeb.Uploads do
  @moduledoc """
  Backend-aware metadata builder for LiveView direct-to-storage (`external:`)
  uploads. Dispatches on the active `Mehungry.Storage` backend:

    * `:supabase` → a signed upload URL the browser `PUT`s to (`Uploaders.Supabase`)
    * `:s3`       → the legacy sigv4 POST-policy form (`Uploaders.S3`)

  Every returned meta carries `:public_url` — the URL the object will have once
  uploaded — so consume callbacks are identical across backends:

      consume_uploaded_entries(socket, :image, fn %{public_url: url}, _ -> {:ok, url} end)
  """

  alias Mehungry.Storage
  alias MehungryWeb.SimpleS3Upload

  @doc "Key for a recipe cover image (preserves the historical layout)."
  def recipe_image_key(entry), do: "recipe_images/#{entry.uuid}.#{ext(entry)}"

  @doc "Key under an arbitrary prefix, e.g. `key_for(\"profile_photos\", entry)`."
  def key_for(prefix, entry), do: "#{prefix}/#{entry.uuid}.#{ext(entry)}"

  @doc """
  LiveView external-upload meta for `entry` targeting `key`. `max_file_size` is
  only used by the legacy S3 POST policy (Supabase enforces size via bucket
  config). Raises if the Supabase backend can't issue a signed URL — the caller
  surfaces that as an upload error.
  """
  def meta(entry, key, max_file_size) do
    case backend() do
      :supabase ->
        {:ok, up} = Storage.signed_upload(key, content_type: entry.client_type)

        %{
          uploader: "Supabase",
          url: up.url,
          headers: up.headers,
          key: up.key,
          public_url: up.public_url
        }

      _ ->
        SimpleS3Upload.meta_with_key(entry, key, max_file_size)
    end
  end

  def ext(entry), do: SimpleS3Upload.ext(entry)

  defp backend, do: Keyword.get(Storage.config(), :backend, :s3)
end
