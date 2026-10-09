defmodule Mehungry.Storage.Behaviour do
  @moduledoc """
  Contract every object-storage backend must satisfy so `Mehungry.Storage` can
  dispatch to AWS S3 or Supabase Storage (and tests can swap in a stub) via the
  `:storage_impl` app config key — same seam pattern as `:instagram_client`.

  Keys are bucket-relative paths (e.g. `"recipe_images/abc.jpg"`); the bucket is
  owned by the backend/config, not passed per call.
  """

  @type key :: String.t()
  @type opts :: keyword()
  @type error :: {:http_error, non_neg_integer(), term()} | {:transport_error, term()}

  @doc "Stores `binary` at `key`. `opts` may carry `:content_type`."
  @callback put(key, binary, opts) :: {:ok, %{key: key, url: String.t()}} | {:error, error}

  @doc "Fetches the object bytes at `key`."
  @callback get(key) :: {:ok, binary} | {:error, error}

  @doc "Deletes the object at `key`."
  @callback delete(key) :: {:ok, term} | {:error, error}

  @doc "Lists object metadata under `prefix` (nil = whole bucket)."
  @callback list(prefix :: String.t() | nil) :: {:ok, [map()]} | {:error, error}

  @doc "Public (unsigned) URL for `key`."
  @callback public_url(key) :: String.t()

  @doc """
  Issues a short-lived credential for a direct browser upload to `key`.

  Returns the HTTP `method`, absolute `url`, request `headers`, the final `key`,
  and the `public_url` the object will have once uploaded.
  """
  @callback signed_upload(key, opts) ::
              {:ok,
               %{
                 method: String.t(),
                 url: String.t(),
                 headers: %{String.t() => String.t()},
                 key: key,
                 public_url: String.t()
               }}
              | {:error, error}
end
