defmodule Mehungry.FoodData.Gutenberg.Client do
  @moduledoc """
  Downloads a Project Gutenberg cookbook as plain UTF-8 text
  (`https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt`).

  A whole book is a single ~100–200 KB document that the
  `Mehungry.FoodData.Gutenberg.BookParser` splits into recipes, so one download
  serves an entire review session. The text is static (the corpus doesn't
  change), so it's cached for a day to avoid re-downloading on every slug patch
  and to be a polite Gutenberg client.

  Behind `Mehungry.FoodData.Gutenberg.ClientBehaviour`; the running app binds the
  `:gutenberg_client` config key to this module, tests bind a stub.
  """

  @behaviour Mehungry.FoodData.Gutenberg.ClientBehaviour

  alias Mehungry.FoodData.Gutenberg.Catalog

  @cache :recipes_cache
  @cache_ttl :timer.hours(24)

  @doc "Returns the configured client module (this module in prod, a stub in tests)."
  def impl, do: Application.get_env(:mehungry, :gutenberg_client, __MODULE__)

  @impl true
  def fetch_book(id) when is_binary(id) and id != "" do
    key = {:gutenberg_book, id}

    case cache_get(key) do
      {:ok, text} when is_binary(text) and text != "" ->
        {:ok, text}

      _ ->
        case get(Catalog.text_url(id)) do
          {:ok, text} ->
            cache_put(key, text)
            {:ok, text}

          {:error, _} = err ->
            err
        end
    end
  end

  def fetch_book(_), do: {:error, :invalid_id}

  # ── cache ───────────────────────────────────────────────────────────────────

  defp cache_get(key) do
    Cachex.get(@cache, key)
  rescue
    _ -> {:ok, nil}
  end

  defp cache_put(key, value) do
    Cachex.put(@cache, key, value, ttl: @cache_ttl)
  rescue
    _ -> :ok
  end

  # ── HTTP ──────────────────────────────────────────────────────────────────

  # Retry transient failures (network errors, 5xx) with backoff; a 404 is
  # deterministic (bad id) so it fails fast.
  defp get(url, attempts \\ 3) do
    case HTTPoison.get(url, [], recv_timeout: 30_000, follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status}} when status >= 500 and attempts > 1 ->
        Process.sleep(backoff_ms(attempts))
        get(url, attempts - 1)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{}} when attempts > 1 ->
        Process.sleep(backoff_ms(attempts))
        get(url, attempts - 1)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp backoff_ms(attempts), do: (4 - attempts) * 600
end
