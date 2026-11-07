defmodule Mehungry.Storage.Behaviour do
  @moduledoc """
  Contract every object-storage backend must satisfy so `Mehungry.Storage` can
  dispatch to AWS S3 or Supabase Storage (and tests can swap in a stub) via the
  `:storage_impl` app config key — same seam pattern as `:instagram_client`.

  Keys are bucket-relative paths (e.g. `"recipe_images/abc.jpg"`). Every call
  defaults to the public media bucket from config; `opts` may carry
  `bucket: :private` to target the private bucket (progress photos — world
  access only via short-lived signed URLs from `signed_url/3`), or an explicit
  bucket name string.
  """

  @type key :: String.t()
  @type opts :: keyword()
  @type error :: {:http_error, non_neg_integer(), term()} | {:transport_error, term()}

  @doc """
  Stores `binary` at `key`. `opts` may carry `:content_type` and `:bucket`.
  `url` is `nil` for private-bucket objects (they have no public URL).
  """
  @callback put(key, binary, opts) ::
              {:ok, %{key: key, url: String.t() | nil}} | {:error, error}

  @doc "Fetches the object bytes at `key`. `opts` may carry `:bucket`."
  @callback get(key, opts) :: {:ok, binary} | {:error, error}

  @doc "Deletes the object at `key`. `opts` may carry `:bucket`."
  @callback delete(key, opts) :: {:ok, term} | {:error, error}

  @doc "Lists object metadata under `prefix` (nil = whole bucket)."
  @callback list(prefix :: String.t() | nil) :: {:ok, [map()]} | {:error, error}

  @doc "Public (unsigned) URL for `key`. Meaningless for the private bucket."
  @callback public_url(key, opts) :: String.t()

  @doc """
  Short-lived read URL for `key`, valid for `expires_in` seconds. The only way
  a client may read a private-bucket object.
  """
  @callback signed_url(key, expires_in :: pos_integer(), opts) ::
              {:ok, String.t()} | {:error, error}

  @doc """
  Bulk `signed_url/3`: one upstream call for many keys. Returns a map of
  `key => signed_url` containing only the keys that signed successfully.
  """
  @callback signed_urls([key], expires_in :: pos_integer(), opts) ::
              {:ok, %{key => String.t()}} | {:error, error}

  @doc """
  Issues a short-lived credential for a direct browser upload to `key`.

  Returns the HTTP `method`, absolute `url`, request `headers`, the final `key`,
  and the `public_url` the object will have once uploaded (`nil` when the
  target bucket is private).
  """
  @callback signed_upload(key, opts) ::
              {:ok,
               %{
                 method: String.t(),
                 url: String.t(),
                 headers: %{String.t() => String.t()},
                 key: key,
                 public_url: String.t() | nil
               }}
              | {:error, error}
end
