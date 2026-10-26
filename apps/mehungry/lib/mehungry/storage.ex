defmodule Mehungry.Storage do
  @moduledoc """
  App-wide object-storage facade. All image/media storage goes through here
  (never raw `ExAws.S3` or inline HTTP) so the backend is a single config flip.

  The active backend is chosen by `config :mehungry, :storage, backend:`
  (`:s3` → `Mehungry.Storage.S3`, `:supabase` → `Mehungry.Storage.Supabase`).
  Tests/rollback can hard-pin a module via `:storage_impl`. Keys are
  bucket-relative paths; the bucket lives in config.

  See `docs/implementation/infrastructure/object_storage.md`.
  """

  alias Mehungry.Storage.{S3, Supabase}

  @doc "Stores `binary` at `key`. Opts: `:content_type`."
  def put(key, binary, opts \\ []), do: impl().put(key, binary, opts)

  @doc "Reads a local file and stores it at `key`. Opts: `:content_type`."
  def put_file(key, path, opts \\ []), do: impl().put(key, File.read!(path), opts)

  @doc "Fetches the object bytes at `key`."
  def get(key), do: impl().get(key)

  @doc "Deletes the object at `key`."
  def delete(key), do: impl().delete(key)

  @doc """
  True if `url` points at storage we own (legacy AWS bucket or our Supabase
  public path) — i.e. safe to delete. Remote/third-party image URLs return false.
  """
  def owned_url?(url) when is_binary(url) do
    String.contains?(url, ".amazonaws.com/") or
      String.contains?(url, "/storage/v1/object/public/")
  end

  def owned_url?(_), do: false

  @doc """
  Deletes the object behind a stored absolute `url`, but only if it's one we own
  (`owned_url?/1`); otherwise a no-op. Safe for recipe/post teardown where the
  URL may be a remote origin image.
  """
  def delete_by_url(url) do
    if owned_url?(url), do: delete(key_from_url(url)), else: {:ok, :skipped}
  end

  @doc "Lists object metadata under `prefix` (nil = whole bucket)."
  def list(prefix \\ nil), do: impl().list(prefix)

  @doc "Public (unsigned) URL for `key`."
  def public_url(key), do: impl().public_url(key)

  @doc "Short-lived credential for a direct browser upload to `key`."
  def signed_upload(key, opts \\ []), do: impl().signed_upload(key, opts)

  @doc """
  Best-effort extraction of a bucket-relative key from a stored absolute URL,
  across every historical host form (legacy AWS virtual-hosted-style, and the
  Supabase public path). Returns the input unchanged if it's already a bare key.

  Used by delete paths and the one-off URL-rewrite migration.
  """
  def key_from_url(nil), do: nil

  def key_from_url(url) when is_binary(url) do
    cond do
      # Supabase public: .../storage/v1/object/public/<bucket>/<key>
      String.contains?(url, "/storage/v1/object/public/") ->
        url
        |> String.split("/storage/v1/object/public/", parts: 2)
        |> List.last()
        |> strip_bucket_segment()

      # AWS virtual-hosted-style: https://<bucket>.s3[.region].amazonaws.com/<key>
      String.contains?(url, ".amazonaws.com/") ->
        url |> String.split(".amazonaws.com/", parts: 2) |> List.last()

      # Already a bare key.
      true ->
        url
    end
    |> strip_query()
  end

  # The Supabase public path embeds the bucket as the first segment after
  # `/public/`; drop it so the returned key matches the AWS key layout.
  defp strip_bucket_segment(path) do
    case String.split(path, "/", parts: 2) do
      [_bucket, key] -> key
      [key] -> key
    end
  end

  defp strip_query(nil), do: nil
  defp strip_query(key), do: key |> String.split("?", parts: 2) |> List.first()

  @doc """
  Whether the active backend has the config it needs to serve uploads. Used by
  the REST upload endpoint to return a clean "not configured" error.
  """
  def configured? do
    case Keyword.get(config(), :backend, :s3) do
      :supabase ->
        present?(Keyword.get(config(), :supabase_url)) and
          present?(Keyword.get(config(), :service_role_key))

      _ ->
        present?(Application.get_env(:mehungry_web, :aws_bucket))
    end
  end

  defp present?(v), do: is_binary(v) and v != ""

  @doc "The resolved storage config keyword list."
  def config, do: Application.get_env(:mehungry, :storage, [])

  defp impl do
    default =
      case Keyword.get(config(), :backend, :s3) do
        :supabase -> Supabase
        _ -> S3
      end

    Application.get_env(:mehungry, :storage_impl, default)
  end
end
