defmodule Mehungry.ReferenceCache do
  @moduledoc """
  Read-through cache for small, **user-independent, rarely-changing** reference
  tables — measurement units, ingredient categories, food-restriction types, and
  the `/foods` linked-compound facet.

  These rows are identical for every user and every render, yet they were queried
  fresh on each LiveView `mount` (basket, calendar, create-recipe, profile, foods),
  so on a busy page they add avoidable load to the small Supabase connection pool.
  This caches them with a 1-hour TTL and **explicit invalidation on the (rare,
  admin-only) writes**, so a curated change still shows up immediately.

  Backed by the `:reference_cache` Cachex instance started in
  `Mehungry.Application`. `fetch/2` falls back to computing the value directly if
  the cache isn't running (defensive — e.g. a unit test that doesn't boot the app).
  """

  @cache :reference_cache
  @ttl :timer.hours(1)

  @doc """
  Return the cached value for `key`, computing it with `fun` (and caching the
  result for #{div(:timer.hours(1), 60_000)} minutes) on a miss.
  """
  @spec fetch(term(), (-> value)) :: value when value: term()
  def fetch(key, fun) when is_function(fun, 0) do
    case Cachex.get(@cache, key) do
      {:ok, nil} ->
        value = fun.()
        Cachex.put(@cache, key, value, ttl: @ttl)
        value

      {:ok, value} ->
        value

      {:error, _} ->
        fun.()
    end
  end

  @doc "Drop a single cached reference key (call on writes to that table)."
  @spec invalidate(term()) :: :ok
  def invalidate(key) do
    Cachex.del(@cache, key)
    :ok
  end

  @doc "Drop every cached reference value. Used by the test setup for isolation."
  @spec clear() :: :ok
  def clear do
    Cachex.clear(@cache)
    :ok
  end
end
