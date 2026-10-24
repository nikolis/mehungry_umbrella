defmodule Mehungry.Storage.Supabase do
  @moduledoc """
  `Mehungry.Storage.Behaviour` over the Supabase Storage REST API.

  Server calls authenticate with the `service_role` key (a server-only secret).
  Browser-direct uploads use short-lived *signed upload URLs* (`signed_upload/2`)
  so the service_role key never leaves the server. Reads are served from the
  public bucket path, matching how the legacy S3 objects were world-readable.
  """

  @behaviour Mehungry.Storage.Behaviour

  require Logger

  @recv_timeout 30_000

  @impl true
  def put(key, binary, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    request(:post, object_path(key), binary, [
      {"Content-Type", content_type},
      {"x-upsert", "true"}
    ])
    |> case do
      {:ok, _body} -> {:ok, %{key: key, url: public_url(key)}}
      error -> error
    end
  end

  @impl true
  def get(key) do
    request(:get, object_path(key), "", [])
  end

  @impl true
  def delete(key) do
    request(:delete, object_path(key), "", [])
  end

  @impl true
  def list(prefix) do
    body = Jason.encode!(%{prefix: prefix || "", limit: 1000, offset: 0})

    case request(:post, "/storage/v1/object/list/#{bucket()}", body, [
           {"Content-Type", "application/json"}
         ]) do
      {:ok, raw} -> {:ok, Jason.decode!(raw)}
      error -> error
    end
  end

  @impl true
  def public_url(key) do
    "#{base_url()}/storage/v1/object/public/#{bucket()}/#{encode_key(key)}"
  end

  @impl true
  def signed_upload(key, _opts) do
    case request(:post, "/storage/v1/object/upload/sign/#{bucket()}/#{encode_key(key)}", "", []) do
      {:ok, raw} ->
        %{"url" => signed_path} = Jason.decode!(raw)

        {:ok,
         %{
           method: "PUT",
           url: "#{base_url()}/storage/v1#{signed_path}",
           headers: %{},
           key: key,
           public_url: public_url(key)
         }}

      error ->
        error
    end
  end

  # ── HTTP ───────────────────────────────────────────────────────────────

  defp request(method, path, body, extra_headers) do
    url = base_url() <> path
    headers = auth_headers() ++ extra_headers

    case HTTPoison.request(method, url, body, headers, recv_timeout: @recv_timeout) do
      {:ok, %HTTPoison.Response{status_code: status, body: resp}} when status in 200..299 ->
        {:ok, resp}

      {:ok, %HTTPoison.Response{status_code: status, body: resp}} ->
        Logger.warning("Supabase storage #{method} #{path} -> #{status}: #{inspect(resp)}")
        {:error, {:http_error, status, resp}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("Supabase storage #{method} #{path} transport error: #{inspect(reason)}")
        {:error, {:transport_error, reason}}
    end
  end

  defp object_path(key), do: "/storage/v1/object/#{bucket()}/#{encode_key(key)}"

  defp auth_headers do
    [{"Authorization", "Bearer #{service_role_key()}"}, {"apikey", service_role_key()}]
  end

  # Keys are `/`-delimited paths; encode each segment so spaces/specials are safe
  # while the path structure is preserved.
  defp encode_key(key) do
    key
    |> String.split("/")
    |> Enum.map(fn seg -> URI.encode(seg, &URI.char_unreserved?/1) end)
    |> Enum.join("/")
  end

  # Accept either the bare project URL (https://<ref>.supabase.co) or the
  # Data API URL the dashboard also shows (…/rest/v1/) — Storage lives at
  # `/storage/v1`, so normalize away any trailing slash or `/rest/v1` suffix.
  defp base_url do
    (cfg(:supabase_url) || raise "SUPABASE_URL not configured")
    |> String.trim_trailing("/")
    |> String.replace_suffix("/rest/v1", "")
    |> String.trim_trailing("/")
  end

  defp service_role_key do
    cfg(:service_role_key) || raise "SUPABASE_SERVICE_ROLE_KEY not configured"
  end

  defp bucket, do: cfg(:bucket)

  defp cfg(k), do: Keyword.get(Mehungry.Storage.config(), k)
end
