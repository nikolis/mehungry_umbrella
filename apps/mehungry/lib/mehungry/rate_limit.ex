defmodule Mehungry.RateLimit do
  @moduledoc """
  Lightweight fixed-window rate limiting backed by the `:rate_limit` Cachex cache
  (started in `Mehungry.Application`). No external dependency.

  A "window" starts on the first hit for a key and the counter is discarded when
  the window's TTL expires, so buckets self-clean.
  """

  @cache :rate_limit

  @doc """
  Records a hit for `key` and reports whether it is within `limit` per
  `window_ms` milliseconds.

  Returns `:ok` if allowed, or `{:error, :rate_limited}` if the limit for the
  current window has been exceeded. Fails open (`:ok`) if the cache is
  unavailable, so a cache hiccup never locks users out.
  """
  def hit(key, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    case Cachex.incr(@cache, key, 1) do
      {:ok, 1} ->
        Cachex.expire(@cache, key, window_ms)
        :ok

      {:ok, count} when count <= limit ->
        :ok

      {:ok, _count} ->
        {:error, :rate_limited}

      _ ->
        :ok
    end
  end
end
