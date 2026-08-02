defmodule Mehungry.Literature.PubTator.Client do
  @moduledoc """
  HTTP client for the NCBI PubTator3 API
  (`www.ncbi.nlm.nih.gov/research/pubtator3-api`).

  Mirrors the retry/rate-limit shape of `Mehungry.Literature.Entrez.Client`:

    * short transient failures (network errors, 5xx, and a `429`/`503` throttle
      whose `Retry-After` is small) are absorbed in-process with bounded
      exponential backoff;
    * a hard throttle is surfaced as `{:error, {:rate_limited, retry_after_s}}`;
    * `404` / an empty result maps to `{:error, :not_found}`.

  It enforces NCBI's ceiling via `Mehungry.RateLimit` before every request —
  **3 requests/second** without an API key, **10/second** with one.

  One endpoint helper:

    * `annotate/2` — export the BioC JSON annotations for a list of PMIDs and parse
      the Chemical / Species / Disease mentions into flat attribute maps.

  The underlying HTTP call resolves through the `:pubtator_http_adapter` app-env
  seam (defaults to `&HTTPoison.get/3`) so tests run without a network round-trip.
  """

  require Logger

  alias Mehungry.RateLimit

  @default_base_url "https://www.ncbi.nlm.nih.gov/research/pubtator3-api"

  @timeout_ms 20_000
  @max_attempts 3
  @retry_base_ms 1_000
  @inline_retry_ceiling_ms 2_000
  @default_retry_after_s 30

  # NCBI's published limits: 3 req/s without an API key, 10 req/s with one.
  @rate_limit_no_key 3
  @rate_limit_with_key 10
  @rate_window_ms 1_000
  @throttle_wait_ms 250
  @throttle_max_waits 8

  # The three entity types this integration captures, mapped to our enum.
  @entity_types %{"Chemical" => "chemical", "Species" => "species", "Disease" => "disease"}

  @doc """
  Export and parse the PubTator3 annotations for a list of PMIDs.

  Returns `{:ok, [mention_attrs], raw_map}` where each `mention_attrs` map carries
  `:entity_type`, `:normalized_identifier` (namespaced, e.g. `"mesh:D000082"` /
  `"ncbitaxon:9606"`, or nil), `:text_span`, `:offset`, and `:confidence`;
  `raw_map` is the decoded payload for the append-only cache. An empty PMID list
  short-circuits with no HTTP.
  """
  @spec annotate([integer() | String.t()], keyword()) ::
          {:ok, [map()], map()} | {:error, term()}
  def annotate(pmids, opts \\ [])

  def annotate([], _opts), do: {:ok, [], %{"documents" => []}}

  def annotate(pmids, _opts) do
    query = URI.encode_query(pmids: Enum.map_join(pmids, ",", &to_string/1))

    with {:ok, body} <- get("/publications/export/biocjson?" <> query) do
      parse_biocjson(body)
    end
  end

  # ── BioC JSON parsing ────────────────────────────────────────────────────────

  defp parse_biocjson(body) do
    with {:ok, documents, raw} <- decode_documents(body) do
      mentions =
        documents
        |> Enum.flat_map(&document_mentions/1)

      {:ok, mentions, raw}
    end
  rescue
    error -> {:error, {:decode, error}}
  end

  # The export is usually a single BioC collection, but can be newline-delimited
  # JSON (one document per line). Handle both, and normalize to a document list.
  defp decode_documents(body) do
    case Jason.decode(body) do
      # PubTator3's /export/biocjson wraps the document list under a "PubTator3" key.
      {:ok, %{"PubTator3" => documents} = raw} when is_list(documents) ->
        {:ok, documents, raw}

      {:ok, %{"documents" => documents} = raw} when is_list(documents) ->
        {:ok, documents, raw}

      {:ok, documents} when is_list(documents) ->
        {:ok, documents, %{"documents" => documents}}

      {:ok, %{"passages" => _} = document} ->
        {:ok, [document], %{"documents" => [document]}}

      {:ok, _other} ->
        {:error, {:decode, :unexpected_shape}}

      {:error, _} ->
        decode_ndjson(body)
    end
  end

  defp decode_ndjson(body) do
    documents =
      body
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode/1)
      |> Enum.flat_map(fn
        {:ok, %{"PubTator3" => docs}} when is_list(docs) -> docs
        {:ok, %{"documents" => docs}} when is_list(docs) -> docs
        {:ok, %{"passages" => _} = doc} -> [doc]
        _ -> []
      end)

    case documents do
      [] -> {:error, {:decode, :unexpected_shape}}
      docs -> {:ok, docs, %{"documents" => docs}}
    end
  end

  defp document_mentions(%{"passages" => passages}) when is_list(passages) do
    Enum.flat_map(passages, &passage_mentions/1)
  end

  defp document_mentions(_), do: []

  defp passage_mentions(%{"annotations" => annotations}) when is_list(annotations) do
    annotations
    |> Enum.map(&mention/1)
    |> Enum.reject(&is_nil/1)
  end

  defp passage_mentions(_), do: []

  defp mention(%{"infons" => infons} = annotation) do
    case Map.get(@entity_types, infons["type"]) do
      nil ->
        nil

      entity_type ->
        raw_identifier = infons["identifier"] || infons["Identifier"]

        %{
          entity_type: entity_type,
          normalized_identifier: normalized_identifier(entity_type, raw_identifier),
          text_span: annotation["text"],
          offset: offset(annotation),
          confidence: parse_float(infons["score"])
        }
    end
  end

  defp mention(_), do: nil

  # Species → NCBI Taxonomy; Chemical / Disease → MeSH. Unnormalized ("-") is nil.
  defp normalized_identifier("species", raw) do
    case strip_prefix(raw) do
      nil -> nil
      id -> "ncbitaxon:" <> id
    end
  end

  defp normalized_identifier(_type, raw) when raw in [nil, "", "-"], do: nil

  defp normalized_identifier(_type, raw) do
    case String.split(raw, ":", parts: 2) do
      [prefix, id] -> String.downcase(prefix) <> ":" <> id
      [id] -> "mesh:" <> id
    end
  end

  defp strip_prefix(raw) when raw in [nil, "", "-"], do: nil

  defp strip_prefix(raw) do
    case String.split(raw, ":", parts: 2) do
      [_prefix, id] -> id
      [id] -> id
    end
  end

  defp offset(%{"locations" => [%{"offset" => offset} | _]}), do: offset
  defp offset(_), do: nil

  # ── HTTP with retry + local rate limiting (mirrors Entrez.Client) ────────────

  @spec get(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp get(path) do
    throttled_get(base_url() <> path, 1, 0)
  end

  defp throttled_get(_url, _attempt, waits) when waits >= @throttle_max_waits do
    {:error, {:rate_limited, 1}}
  end

  defp throttled_get(url, attempt, waits) do
    case RateLimit.hit("pubtator", rate_limit(), @rate_window_ms) do
      :ok ->
        do_get(url, attempt)

      {:error, :rate_limited} ->
        Process.sleep(@throttle_wait_ms)
        throttled_get(url, attempt, waits + 1)
    end
  end

  defp do_get(url, attempt) do
    case adapter().(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: code, headers: headers}} when code in [429, 503] ->
        handle_throttle(url, attempt, retry_after_seconds(headers))

      {:ok, %{status_code: code}} when code >= 500 ->
        retry_or(url, attempt, {:http, code}, "server error #{code}")

      {:ok, %{status_code: code}} ->
        {:error, {:http, code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        retry_or(url, attempt, {:network, reason}, "network error #{inspect(reason)}")
    end
  end

  defp handle_throttle(_url, attempt, retry_after) when attempt >= @max_attempts do
    {:error, {:rate_limited, retry_after || @default_retry_after_s}}
  end

  defp handle_throttle(_url, _attempt, retry_after)
       when is_integer(retry_after) and retry_after * 1_000 > @inline_retry_ceiling_ms do
    {:error, {:rate_limited, retry_after}}
  end

  defp handle_throttle(url, attempt, retry_after) do
    delay = inline_delay(retry_after, attempt)
    Logger.warning("PubTator.Client: throttled, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp retry_or(_url, attempt, error, _desc) when attempt >= @max_attempts do
    {:error, error}
  end

  defp retry_or(url, attempt, _error, desc) do
    delay = backoff_ms(attempt)
    Logger.warning("PubTator.Client: #{desc}, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp inline_delay(nil, attempt), do: backoff_ms(attempt)
  defp inline_delay(retry_after, _attempt), do: retry_after * 1_000

  defp backoff_ms(attempt), do: round(@retry_base_ms * :math.pow(2, attempt - 1))

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp retry_after_seconds(headers) do
    case header(headers, "retry-after") do
      nil -> nil
      value -> parse_int(value)
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(k) == name, do: v end)
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_float(_), do: nil

  # ── config seams ────────────────────────────────────────────────────────────

  defp adapter, do: Application.get_env(:mehungry, :pubtator_http_adapter, &HTTPoison.get/3)

  defp base_url, do: Application.get_env(:mehungry, :pubtator_base_url, @default_base_url)

  # PubTator3 shares the NCBI host, so it reuses the Entrez API key when set.
  defp api_key, do: Application.get_env(:mehungry, :entrez_api_key)

  defp rate_limit do
    default = if api_key() in [nil, ""], do: @rate_limit_no_key, else: @rate_limit_with_key
    Application.get_env(:mehungry, :pubtator_rate_limit, default)
  end
end
