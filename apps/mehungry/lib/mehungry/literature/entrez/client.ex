defmodule Mehungry.Literature.Entrez.Client do
  @moduledoc """
  HTTP client for the NCBI Entrez E-utilities API
  (`eutils.ncbi.nlm.nih.gov/entrez/eutils`).

  Mirrors the retry/rate-limit shape of `Mehungry.Chemistry.PubChem.Client`:

    * short transient failures (network errors, 5xx, and a `429`/`503` throttle
      whose `Retry-After` is small) are absorbed in-process with bounded
      exponential backoff;
    * a hard throttle is surfaced as `{:error, {:rate_limited, retry_after_s}}` so
      a caller can back off rather than hammer the API;
    * `404` maps to `{:error, :not_found}`.

  It enforces NCBI's documented ceiling via `Mehungry.RateLimit` before every
  request — **3 requests/second** without an API key, **10/second** with one.

  Two endpoint helpers:

    * `esearch/2` — resolve a search term to a list of PMIDs (JSON).
    * `efetch/2`  — fetch the bibliographic records for PMIDs (XML, parsed via
      `SweetXml` into flat attribute maps).

  The underlying HTTP call resolves through the `:entrez_http_adapter` app-env
  seam (defaults to `&HTTPoison.get/3`) so tests run without a network round-trip.
  """

  require Logger

  import SweetXml

  alias Mehungry.RateLimit

  @default_base_url "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

  @timeout_ms 20_000
  @max_attempts 3
  @retry_base_ms 1_000
  # A throttle whose `Retry-After` is at or below this is worth absorbing in-process.
  @inline_retry_ceiling_ms 2_000
  @default_retry_after_s 30

  # NCBI's published limits: 3 req/s without an API key, 10 req/s with one.
  @rate_limit_no_key 3
  @rate_limit_with_key 10
  @rate_window_ms 1_000
  # Spread-out wait when we would exceed the local rate window.
  @throttle_wait_ms 250
  @throttle_max_waits 8

  @default_retmax 20

  @doc """
  Resolve a search term to a list of PubMed IDs.

  Options: `:retmax` (default #{@default_retmax}), `:retstart` (default 0),
  `:mindate` / `:maxdate` (`"YYYY/MM/DD"` strings, for an incremental re-crawl).

  Returns `{:ok, [pmid], total_count, raw_json}` — `raw_json` is the full decoded
  payload for the append-only cache — or `{:error, reason}`.
  """
  @spec esearch(String.t(), keyword()) ::
          {:ok, [integer()], non_neg_integer(), map()} | {:error, term()}
  def esearch(term, opts \\ []) do
    params =
      [
        db: "pubmed",
        term: term,
        retmode: "json",
        retmax: Keyword.get(opts, :retmax, @default_retmax),
        retstart: Keyword.get(opts, :retstart, 0)
      ]
      |> maybe_put(:datetype, if(opts[:mindate] || opts[:maxdate], do: "pdat"))
      |> maybe_put(:mindate, opts[:mindate])
      |> maybe_put(:maxdate, opts[:maxdate])
      |> with_api_key()

    with {:ok, body} <- get("/esearch.fcgi", params) do
      parse_esearch(body)
    end
  end

  @doc """
  Fetch the bibliographic records for a list of PMIDs.

  Returns `{:ok, [study_attrs], raw_map}` where each `study_attrs` map carries
  `:pmid`, `:doi`, `:title`, `:abstract`, `:journal`, `:publication_date`,
  `:authors`, and `raw_map` is the decoded payload for the cache. An empty PMID
  list short-circuits to `{:ok, [], %{"articles" => []}}` with no HTTP.
  """
  @spec efetch([integer() | String.t()], keyword()) ::
          {:ok, [map()], map()} | {:error, term()}
  def efetch(pmids, opts \\ [])

  def efetch([], _opts), do: {:ok, [], %{"articles" => []}}

  def efetch(pmids, _opts) do
    params =
      [db: "pubmed", id: Enum.map_join(pmids, ",", &to_string/1), retmode: "xml"]
      |> with_api_key()

    with {:ok, body} <- get("/efetch.fcgi", params) do
      parse_efetch(body)
    end
  end

  # ── esearch parsing ─────────────────────────────────────────────────────────

  defp parse_esearch(body) do
    case Jason.decode(body) do
      {:ok, %{"esearchresult" => result} = decoded} ->
        pmids =
          result
          |> Map.get("idlist", [])
          |> Enum.map(&parse_int/1)
          |> Enum.reject(&is_nil/1)

        count = parse_int(result["count"]) || length(pmids)
        {:ok, pmids, count, decoded}

      {:ok, _other} ->
        {:error, {:decode, :unexpected_shape}}

      {:error, reason} ->
        {:error, {:decode, reason}}
    end
  end

  # ── efetch parsing (PubMed XML → flat attr maps) ────────────────────────────

  defp parse_efetch(body) do
    articles =
      body
      |> xpath(
        ~x"//PubmedArticle"l,
        pmid: ~x"./MedlineCitation/PMID/text()"s,
        title: ~x"./MedlineCitation/Article/ArticleTitle/text()"s,
        abstract_parts: ~x"./MedlineCitation/Article/Abstract/AbstractText/text()"ls,
        journal: ~x"./MedlineCitation/Article/Journal/Title/text()"s,
        year: ~x"./MedlineCitation/Article/Journal/JournalIssue/PubDate/Year/text()"s,
        month: ~x"./MedlineCitation/Article/Journal/JournalIssue/PubDate/Month/text()"s,
        day: ~x"./MedlineCitation/Article/Journal/JournalIssue/PubDate/Day/text()"s,
        medline_date:
          ~x"./MedlineCitation/Article/Journal/JournalIssue/PubDate/MedlineDate/text()"s,
        doi: ~x"./PubmedData/ArticleIdList/ArticleId[@IdType='doi']/text()"s,
        authors: [
          ~x"./MedlineCitation/Article/AuthorList/Author"l,
          last_name: ~x"./LastName/text()"s,
          fore_name: ~x"./ForeName/text()"s
        ]
      )
      |> Enum.map(&normalize_article/1)
      |> Enum.reject(&is_nil(&1.pmid))

    {:ok, articles, %{"raw_xml" => body, "articles" => Enum.map(articles, &stringify/1)}}
  rescue
    error -> {:error, {:decode, error}}
  end

  defp normalize_article(raw) do
    %{
      pmid: parse_int(raw.pmid),
      doi: blank_to_nil(raw.doi),
      title: blank_to_nil(raw.title),
      abstract: join_abstract(raw.abstract_parts),
      journal: blank_to_nil(raw.journal),
      publication_date: publication_date(raw),
      authors: authors(raw.authors)
    }
  end

  defp join_abstract([]), do: nil

  defp join_abstract(parts) do
    parts
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> blank_to_nil()
  end

  # Prefer the structured Year/Month/Day; fall back to the free-form MedlineDate.
  defp publication_date(%{year: year, month: month, day: day, medline_date: medline}) do
    case String.trim(year) do
      "" -> blank_to_nil(String.trim(medline))
      y -> [y, String.trim(month), String.trim(day)] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
    end
  end

  defp authors(list) do
    list
    |> Enum.map(fn %{last_name: last, fore_name: fore} ->
      [String.trim(fore), String.trim(last)] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp stringify(%{authors: authors} = article) do
    article
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("authors", authors)
  end

  # ── HTTP with retry + local rate limiting ───────────────────────────────────

  @spec get(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp get(path, params) do
    url = base_url() <> path <> "?" <> URI.encode_query(params)
    throttled_get(url, 1, 0)
  end

  # Enforce the local rate window before issuing the request. When the window is
  # full, wait a beat and re-check rather than firing (and eating a remote 429).
  defp throttled_get(_url, _attempt, waits) when waits >= @throttle_max_waits do
    {:error, {:rate_limited, 1}}
  end

  defp throttled_get(url, attempt, waits) do
    case RateLimit.hit("entrez", rate_limit(), @rate_window_ms) do
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
    Logger.warning("Entrez.Client: throttled, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp retry_or(_url, attempt, error, _desc) when attempt >= @max_attempts do
    {:error, error}
  end

  defp retry_or(url, attempt, _error, desc) do
    delay = backoff_ms(attempt)
    Logger.warning("Entrez.Client: #{desc}, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp inline_delay(nil, attempt), do: backoff_ms(attempt)
  defp inline_delay(retry_after, _attempt), do: retry_after * 1_000

  defp backoff_ms(attempt), do: round(@retry_base_ms * :math.pow(2, attempt - 1))

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Keyword.put(params, key, value)

  defp with_api_key(params) do
    case api_key() do
      key when is_binary(key) and key != "" -> Keyword.put(params, :api_key, key)
      _ -> params
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

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  # ── config seams ────────────────────────────────────────────────────────────

  defp adapter, do: Application.get_env(:mehungry, :entrez_http_adapter, &HTTPoison.get/3)

  defp base_url, do: Application.get_env(:mehungry, :entrez_base_url, @default_base_url)

  defp api_key, do: Application.get_env(:mehungry, :entrez_api_key)

  # Overridable so tests can lift the local throttle; production holds NCBI's
  # published ceiling (higher when an API key is configured).
  defp rate_limit do
    default = if api_key() in [nil, ""], do: @rate_limit_no_key, else: @rate_limit_with_key
    Application.get_env(:mehungry, :entrez_rate_limit, default)
  end
end
