defmodule Mehungry.Chemistry.PubChem.Client do
  @moduledoc """
  HTTP client for the PubChem PUG REST API (`pubchem.ncbi.nlm.nih.gov/rest/pug`).

  Mirrors the retry/rate-limit shape of `Mehungry.FoodData.Usda.FdcHttp`:

    * short transient failures (network errors, 5xx, and PubChem's `503`
      throttle whose `Retry-After` is small) are absorbed in-process with bounded
      exponential backoff;
    * a hard throttle is surfaced as `{:error, {:rate_limited, retry_after_s}}` so
      a caller can back off rather than hammer the API;
    * `404` / `PUGREST.NotFound` maps to `{:error, :not_found}`.

  On top of that it enforces PubChem's documented ceiling of **5 requests/second**
  via `Mehungry.RateLimit` before every request.

  The three endpoint helpers each return `{:ok, parsed, raw_json, meta}` where
  `raw_json` is the full decoded payload (for the append-only response cache) and
  `meta` carries the `etag` / `api_version` headers.

  The underlying HTTP call resolves through the `:pubchem_http_adapter` app-env
  seam (defaults to `&HTTPoison.get/3`) so tests run without a network round-trip.
  """

  require Logger

  alias Mehungry.RateLimit

  @default_base_url "https://pubchem.ncbi.nlm.nih.gov/rest/pug"

  @timeout_ms 15_000
  @max_attempts 3
  @retry_base_ms 1_000
  # A 503 whose `Retry-After` is at or below this is worth absorbing in-process.
  @inline_retry_ceiling_ms 2_000
  @default_retry_after_s 30

  # PubChem's published limit: no more than 5 requests per second.
  @rate_limit 5
  @rate_window_ms 1_000
  # Spread-out wait when we would exceed the local rate window.
  @throttle_wait_ms 250
  @throttle_max_waits 8

  @property_fields "Title,IUPACName,MolecularFormula,CanonicalSMILES,IsomericSMILES,InChI,InChIKey"

  @type meta :: %{etag: String.t() | nil, api_version: String.t() | nil}

  @doc "Resolve a compound name to its first PubChem CID."
  @spec name_to_cids(String.t()) ::
          {:ok, pos_integer(), map(), meta()} | {:error, term()}
  def name_to_cids(name) do
    with {:ok, body, meta} <-
           get("/compound/name/#{URI.encode(name, &URI.char_unreserved?/1)}/cids/JSON") do
      case get_in(body, ["IdentifierList", "CID"]) do
        [cid | _] when is_integer(cid) -> {:ok, cid, body, meta}
        _ -> {:error, :not_found}
      end
    end
  end

  @doc """
  Fetch the identity properties for a CID, normalized into a flat map with
  `:title`, `:iupac_name`, `:molecular_formula`, `:smiles`, `:isomeric_smiles`,
  `:inchi`, `:inchikey`. Reads SMILES defensively: PubChem is renaming
  `CanonicalSMILES` → `SMILES`, so either is accepted.
  """
  @spec properties(pos_integer()) :: {:ok, map(), map(), meta()} | {:error, term()}
  def properties(cid) do
    with {:ok, body, meta} <- get("/compound/cid/#{cid}/property/#{@property_fields}/JSON") do
      case get_in(body, ["PropertyTable", "Properties"]) do
        [props | _] when is_map(props) -> {:ok, normalize_properties(props), body, meta}
        _ -> {:error, :not_found}
      end
    end
  end

  @doc "Fetch the synonym list for a CID (may be long; PubChem orders by relevance)."
  @spec synonyms(pos_integer()) :: {:ok, [String.t()], map(), meta()} | {:error, term()}
  def synonyms(cid) do
    with {:ok, body, meta} <- get("/compound/cid/#{cid}/synonyms/JSON") do
      case get_in(body, ["InformationList", "Information"]) do
        [%{"Synonym" => syns} | _] when is_list(syns) -> {:ok, syns, body, meta}
        _ -> {:ok, [], body, meta}
      end
    end
  end

  # ── internals ────────────────────────────────────────────────────────────────

  defp normalize_properties(props) do
    %{
      title: props["Title"],
      iupac_name: props["IUPACName"],
      molecular_formula: props["MolecularFormula"],
      smiles: props["SMILES"] || props["CanonicalSMILES"] || props["ConnectivitySMILES"],
      isomeric_smiles: props["IsomericSMILES"],
      inchi: props["InChI"],
      inchikey: props["InChIKey"]
    }
  end

  @spec get(String.t()) :: {:ok, map(), meta()} | {:error, term()}
  defp get(path), do: throttled_get(base_url() <> path, 1, 0)

  # Enforce the local 5-req/s window before issuing the request. When the window
  # is full, wait a beat and re-check rather than firing (and eating a remote 503).
  defp throttled_get(_url, _attempt, waits) when waits >= @throttle_max_waits do
    {:error, {:rate_limited, 1}}
  end

  defp throttled_get(url, attempt, waits) do
    case RateLimit.hit("pubchem", rate_limit(), @rate_window_ms) do
      :ok ->
        do_get(url, attempt)

      {:error, :rate_limited} ->
        Process.sleep(@throttle_wait_ms)
        throttled_get(url, attempt, waits + 1)
    end
  end

  defp do_get(url, attempt) do
    case adapter().(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body, headers: headers}} ->
        decode(body, headers)

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: 503, headers: headers}} ->
        handle_throttle(url, attempt, retry_after_seconds(headers))

      {:ok, %{status_code: code}} when code >= 500 ->
        retry_or(url, attempt, {:http, code}, "server error #{code}")

      {:ok, %{status_code: code}} ->
        {:error, {:http, code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        retry_or(url, attempt, {:network, reason}, "network error #{inspect(reason)}")
    end
  end

  # Hard throttle (out of inline budget, or the advertised wait is too long to
  # block on) → surface the wait. Otherwise sleep and retry in-process.
  defp handle_throttle(_url, attempt, retry_after) when attempt >= @max_attempts do
    {:error, {:rate_limited, retry_after || @default_retry_after_s}}
  end

  defp handle_throttle(_url, _attempt, retry_after)
       when is_integer(retry_after) and retry_after * 1_000 > @inline_retry_ceiling_ms do
    {:error, {:rate_limited, retry_after}}
  end

  defp handle_throttle(url, attempt, retry_after) do
    delay = inline_delay(retry_after, attempt)

    Logger.warning(
      "PubChem.Client: 503 throttle, retrying in #{delay}ms (attempt #{attempt + 1})"
    )

    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp retry_or(_url, attempt, error, _desc) when attempt >= @max_attempts do
    {:error, error}
  end

  defp retry_or(url, attempt, _error, desc) do
    delay = backoff_ms(attempt)
    Logger.warning("PubChem.Client: #{desc}, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp inline_delay(nil, attempt), do: backoff_ms(attempt)
  defp inline_delay(retry_after, _attempt), do: retry_after * 1_000

  defp backoff_ms(attempt), do: round(@retry_base_ms * :math.pow(2, attempt - 1))

  defp decode(body, headers) do
    case Jason.decode(body) do
      {:ok, map} ->
        {:ok, map,
         %{etag: header(headers, "etag"), api_version: header(headers, "x-pubchem-version")}}

      {:error, reason} ->
        {:error, {:decode, reason}}
    end
  end

  defp retry_after_seconds(headers) do
    case header(headers, "retry-after") do
      nil -> nil
      value -> parse_int(value)
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(k) == name, do: v end)
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp adapter, do: Application.get_env(:mehungry, :pubchem_http_adapter, &HTTPoison.get/3)

  defp base_url, do: Application.get_env(:mehungry, :pubchem_base_url, @default_base_url)

  # Overridable so tests can lift the local throttle out of the way; production
  # holds PubChem's published 5 req/s ceiling.
  defp rate_limit, do: Application.get_env(:mehungry, :pubchem_rate_limit, @rate_limit)
end
