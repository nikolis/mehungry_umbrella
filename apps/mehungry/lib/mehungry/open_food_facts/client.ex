defmodule Mehungry.OpenFoodFacts.Client do
  @moduledoc """
  HTTP client for Open Food Facts.

  - Product read API (v2) for single-barcode lookups — rate-limited by OFF to
    100 req/min, so bulk data must always come from the static dumps.
  - Static host downloads: the full JSONL dump and the daily delta files.

  OFF requires an identifying User-Agent on every request.
  No API key is needed.
  """

  @behaviour Mehungry.OpenFoodFacts.ClientBehaviour

  require Logger

  @timeout_ms 30_000
  # Full-dump downloads run for a long time; only bound inactivity per chunk.
  @download_chunk_timeout_ms 60_000

  @impl true
  def fetch_product(barcode) do
    url = "#{base_url()}/api/v2/product/#{barcode}.json"

    case HTTPoison.get(url, headers(), recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"status" => 1, "product" => product}} -> {:ok, product}
          {:ok, %{"status" => 0}} -> {:error, :not_found}
          {:ok, _other} -> {:error, "unexpected OFF product response shape"}
          {:error, reason} -> {:error, "OFF product JSON parse error: #{inspect(reason)}"}
        end

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: code}} ->
        {:error, "OFF product HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "OFF product network error: #{inspect(reason)}"}
    end
  end

  @impl true
  def fetch_delta_index do
    url = "#{static_url()}/data/delta/index.txt"

    case HTTPoison.get(url, headers(), recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} ->
        filenames =
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))

        {:ok, filenames}

      {:ok, %{status_code: code}} ->
        {:error, "OFF delta index HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "OFF delta index network error: #{inspect(reason)}"}
    end
  end

  @impl true
  def download_delta(filename, dest_path) do
    download_to_file("#{static_url()}/data/delta/#{filename}", dest_path)
  end

  @impl true
  def download_dump(dest_path) do
    download_to_file("#{static_url()}/data/openfoodfacts-products.jsonl.gz", dest_path)
  end

  # ── private ──────────────────────────────────────────────────────────────────

  # Streams an HTTP body to disk chunk by chunk (constant memory), so the
  # ~10 GB full dump never has to fit in RAM.
  defp download_to_file(url, dest_path) do
    Logger.info("[OFF.Client] Downloading #{url} -> #{dest_path}")
    file = File.open!(dest_path, [:write, :binary])

    try do
      case HTTPoison.get(url, headers(),
             stream_to: self(),
             async: :once,
             recv_timeout: @download_chunk_timeout_ms,
             follow_redirect: true
           ) do
        {:ok, %HTTPoison.AsyncResponse{id: id}} ->
          receive_download(id, file)

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "OFF download error: #{inspect(reason)}"}
      end
    after
      File.close(file)
    end
    |> case do
      :ok ->
        :ok

      {:error, _} = error ->
        File.rm(dest_path)
        error
    end
  end

  defp receive_download(id, file) do
    HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})

    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: 200} ->
        receive_download(id, file)

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        {:error, "OFF download HTTP #{code}"}

      %HTTPoison.AsyncHeaders{id: ^id} ->
        receive_download(id, file)

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        IO.binwrite(file, chunk)
        receive_download(id, file)

      %HTTPoison.AsyncEnd{id: ^id} ->
        :ok

      %HTTPoison.Error{id: ^id, reason: reason} ->
        {:error, "OFF download network error: #{inspect(reason)}"}
    after
      @download_chunk_timeout_ms ->
        {:error, "OFF download timed out waiting for data"}
    end
  end

  defp headers do
    [{"User-Agent", user_agent()}, {"Accept", "application/json"}]
  end

  defp user_agent do
    contact = Application.get_env(:mehungry, :off_contact_email, "nikolisgal@gmail.com")
    "Mehungry/1.0 (#{contact})"
  end

  defp base_url do
    Application.get_env(:mehungry, :off_base_url, "https://world.openfoodfacts.org")
  end

  defp static_url do
    Application.get_env(:mehungry, :off_static_url, "https://static.openfoodfacts.org")
  end
end
