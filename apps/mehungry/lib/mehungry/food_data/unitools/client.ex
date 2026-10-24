defmodule Mehungry.FoodData.UniTools.Client do
  @moduledoc """
  Loads a UniTools World Recipes dataset from the JSON file bundled under the
  `:mehungry` app's `priv/` directory (see `Mehungry.FoodData.UniTools.Catalog`).

  The whole dataset is a single ~2.6 MB document (501 recipes + wrapper metadata)
  that `Mehungry.FoodData.UniTools.Decoder` splits into recipes, so one read
  serves an entire review session. It's bundled (not fetched) — offline-safe and
  deterministic — but still decoded once and cached for a day to avoid re-reading
  and re-parsing on every recipe patch.

  Behind `Mehungry.FoodData.UniTools.ClientBehaviour`; the running app binds the
  `:unitools_client` config key to this module (via `impl/0`'s default), tests
  bind a stub.
  """

  @behaviour Mehungry.FoodData.UniTools.ClientBehaviour

  alias Mehungry.FoodData.UniTools.Catalog

  @cache :recipes_cache
  @cache_ttl :timer.hours(24)

  @doc "Returns the configured client module (this module in prod, a stub in tests)."
  def impl, do: Application.get_env(:mehungry, :unitools_client, __MODULE__)

  @impl true
  def load_dataset(id) when is_binary(id) and id != "" do
    key = {:unitools_dataset, id}

    case cache_get(key) do
      {:ok, %{} = data} ->
        {:ok, data}

      _ ->
        with %{path: path} <- Catalog.get(id),
             {:ok, body} <- File.read(file_path(path)),
             {:ok, data} <- Jason.decode(body) do
          cache_put(key, data)
          {:ok, data}
        else
          nil -> {:error, :unknown_dataset}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def load_dataset(_), do: {:error, :invalid_id}

  defp file_path(path), do: Application.app_dir(:mehungry, Path.join("priv", path))

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
end
