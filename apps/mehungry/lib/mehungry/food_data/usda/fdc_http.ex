defmodule Mehungry.FoodData.Usda.FdcHttp do
  @moduledoc """
  Shared HTTP layer for USDA FoodData Central (`api.nal.usda.gov`) GET requests.

  Every FDC caller (`FdcClient.fetch_food/1`, `FdcClient.lookup/1`,
  `SearchClient`) goes through `get/1` so rate-limit handling lives in one place.
  It:

    * absorbs short transient failures in-process with bounded exponential
      backoff — network timeouts, 5xx, and 429s whose `Retry-After` is small;
    * surfaces a hard 429 as `{:error, {:rate_limited, retry_after_seconds}}` so
      an Oban worker can snooze the job instead of blocking a worker slot for
      minutes; and
    * returns the parsed JSON body plus rate-limit metadata (the
      `x-ratelimit-remaining` header) so callers can throttle proactively.

  Mirrors the retry shape of `Mehungry.AI.Client`, adding the `Retry-After`
  awareness that client lacks.

  The underlying HTTP call is resolved through the `:fdc_http_adapter` app-env
  seam (defaults to `&HTTPoison.get/3`) so tests can stub responses without a
  network round-trip.
  """

  require Logger

  @timeout_ms 15_000
  # Total attempts (initial try + retries) for transient failures.
  @max_attempts 3
  @retry_base_ms 1_000
  # A 429 whose `Retry-After` is at or below this is worth absorbing in-process;
  # a longer wait is surfaced so the caller can reschedule rather than block.
  @inline_retry_ceiling_ms 2_000
  # Fallback wait reported on a hard 429 that carries no `Retry-After` header.
  @default_retry_after_s 60

  @type meta :: %{remaining: non_neg_integer() | nil}
  @type result ::
          {:ok, map(), meta()}
          | {:error, {:rate_limited, non_neg_integer()}}
          | {:error, :not_found}
          | {:error, {:http, non_neg_integer()}}
          | {:error, {:network, term()}}
          | {:error, {:decode, term()}}

  @doc """
  GETs an FDC URL and returns the decoded body with rate-limit metadata, or a
  structured error. See the moduledoc for the retry/rate-limit contract.
  """
  @spec get(String.t()) :: result()
  def get(url), do: do_get(url, 1)

  # ── internals ────────────────────────────────────────────────────────────────

  defp do_get(url, attempt) do
    case adapter().(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body, headers: headers}} ->
        decode(body, headers)

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: 429, headers: headers}} ->
        handle_rate_limit(url, attempt, retry_after_seconds(headers))

      {:ok, %{status_code: code}} when code >= 500 ->
        retry_or(url, attempt, {:http, code}, "server error #{code}")

      {:ok, %{status_code: code}} ->
        {:error, {:http, code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        retry_or(url, attempt, {:network, reason}, "network error #{inspect(reason)}")
    end
  end

  # Hard 429 (no more inline budget, or the advertised wait is too long to block
  # on) → surface the wait so the caller can reschedule. Otherwise sleep and
  # retry in-process.
  defp handle_rate_limit(_url, attempt, retry_after) when attempt >= @max_attempts do
    {:error, {:rate_limited, retry_after || @default_retry_after_s}}
  end

  defp handle_rate_limit(_url, _attempt, retry_after)
       when is_integer(retry_after) and retry_after * 1_000 > @inline_retry_ceiling_ms do
    {:error, {:rate_limited, retry_after}}
  end

  defp handle_rate_limit(url, attempt, retry_after) do
    delay = inline_delay(retry_after, attempt)
    Logger.warning("FdcHttp: 429, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp retry_or(_url, attempt, error, _desc) when attempt >= @max_attempts do
    {:error, error}
  end

  defp retry_or(url, attempt, _error, desc) do
    delay = backoff_ms(attempt)
    Logger.warning("FdcHttp: #{desc}, retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    do_get(url, attempt + 1)
  end

  defp inline_delay(nil, attempt), do: backoff_ms(attempt)
  defp inline_delay(retry_after, _attempt), do: retry_after * 1_000

  # attempt is 1-based, so exponent starts at 0 for the first retry.
  defp backoff_ms(attempt), do: round(@retry_base_ms * :math.pow(2, attempt - 1))

  defp decode(body, headers) do
    case Jason.decode(body) do
      {:ok, map} -> {:ok, map, %{remaining: header_int(headers, "x-ratelimit-remaining")}}
      {:error, reason} -> {:error, {:decode, reason}}
    end
  end

  defp retry_after_seconds(headers), do: header_int(headers, "retry-after")

  defp header_int(headers, name) do
    headers
    |> Enum.find_value(fn {k, v} -> if String.downcase(k) == name, do: v end)
    |> parse_int()
  end

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp adapter, do: Application.get_env(:mehungry, :fdc_http_adapter, &HTTPoison.get/3)
end
