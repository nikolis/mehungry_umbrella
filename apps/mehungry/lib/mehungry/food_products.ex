defmodule Mehungry.FoodProducts do
  @moduledoc """
  Retail food products identified by GTIN/EAN barcode, sourced from
  Open Food Facts (OFF).

  Data arrives through three paths that share `upsert_products/1`:
  the one-time bulk import (`Mehungry.OpenFoodFacts.BulkImporter`), the
  weekly delta sync (`Mehungry.ObanWorkers.OffDeltaSyncWorker`), and the
  live API fallback inside `get_product_by_barcode/2`.

  Product data is ODbL-licensed — attribution to Open Food Facts is required
  wherever it is displayed.
  """

  import Ecto.Query

  require Logger

  alias Mehungry.FoodProducts.FoodProduct
  alias Mehungry.FoodProducts.FoodProductTranslation
  alias Mehungry.FoodProducts.SyncState
  alias Mehungry.Languages
  alias Mehungry.OpenFoodFacts.ProductParser
  alias Mehungry.Repo

  @max_search_results 20
  @search_threshold 0.3
  # How long a "barcode not on OFF" answer is cached before we ask OFF again.
  @negative_cache_ttl :timer.minutes(10)

  # ═════════════════════════════════════════════════════════════════════════
  # Lookup
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Looks up a product by barcode — the barcode-scan entry point.

  Local DB first; on a miss, falls back to the live OFF API (pass
  `fallback: false` to disable), caching whatever it finds. Products fetched
  through the fallback are kept even when not sold in Europe: a user scanned
  them, so they are relevant.

  Returns `{:ok, %FoodProduct{}}` (translations + ingredient preloaded),
  `{:error, :invalid_barcode}`, `{:error, :not_found}`, or
  `{:error, :off_unavailable}` when OFF cannot be reached.
  """
  def get_product_by_barcode(barcode, opts \\ []) do
    case ProductParser.normalize_barcode(barcode) do
      {:ok, normalized} ->
        case get_local_product(normalized) do
          %FoodProduct{} = product ->
            {:ok, product}

          nil ->
            if Keyword.get(opts, :fallback, true) do
              fetch_from_off(normalized)
            else
              {:error, :not_found}
            end
        end

      :skip ->
        {:error, :invalid_barcode}
    end
  end

  defp get_local_product(barcode) do
    FoodProduct
    |> Repo.get_by(barcode: barcode)
    |> case do
      nil -> nil
      product -> Repo.preload(product, [:translations, :ingredient])
    end
  end

  defp fetch_from_off(barcode) do
    case Cachex.get(:off_lookup_cache, barcode) do
      {:ok, :not_found} ->
        {:error, :not_found}

      _ ->
        do_fetch_from_off(barcode)
    end
  end

  defp do_fetch_from_off(barcode) do
    case off_client().fetch_product(barcode) do
      {:ok, product_map} ->
        case ProductParser.parse_api_product(product_map, known_language_codes()) do
          {:ok, attrs, translations} ->
            upsert_products([{attrs, translations}])
            {:ok, get_local_product(attrs.barcode)}

          :skip ->
            cache_miss(barcode)
            {:error, :not_found}
        end

      {:error, :not_found} ->
        cache_miss(barcode)
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("[FoodProducts] OFF fallback failed for #{barcode}: #{inspect(reason)}")
        {:error, :off_unavailable}
    end
  rescue
    error ->
      Logger.warning("[FoodProducts] OFF fallback crashed for #{barcode}: #{inspect(error)}")
      {:error, :off_unavailable}
  end

  defp cache_miss(barcode) do
    Cachex.put(:off_lookup_cache, barcode, :not_found, ttl: @negative_cache_ttl)
  end

  # ═════════════════════════════════════════════════════════════════════════
  # Search / listing
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Fuzzy product search over product names and their translations
  (pg_trgm `word_similarity`, accent-insensitive).

  Options: `:limit` (default #{@max_search_results}), `:country` (OFF tag,
  e.g. `"en:greece"`).
  """
  def search_products(query, opts \\ []) do
    query = String.trim(query || "")

    if query == "" do
      []
    else
      limit = Keyword.get(opts, :limit, @max_search_results)

      translation_ids =
        from t in FoodProductTranslation,
          where:
            fragment(
              "word_similarity(unaccent(?), unaccent(?)) > ?",
              ^query,
              t.name,
              ^@search_threshold
            ),
          select: t.food_product_id

      base =
        from p in FoodProduct,
          where:
            fragment(
              "word_similarity(unaccent(?), unaccent(?)) > ?",
              ^query,
              p.name,
              ^@search_threshold
            ) or p.id in subquery(translation_ids),
          order_by: [
            desc: fragment("word_similarity(unaccent(?), unaccent(?))", ^query, p.name),
            desc: p.completeness,
            asc: fragment("LENGTH(?)", p.name)
          ],
          limit: ^limit,
          preload: [:translations]

      base
      |> maybe_filter_country(Keyword.get(opts, :country))
      |> Repo.all()
    end
  end

  @doc """
  Lists products sold in a country, by OFF tag (e.g. `"en:greece"`),
  most complete records first. Options: `:limit` (default 50), `:offset`.
  """
  def list_products_by_country(country_tag, opts \\ []) do
    from(p in FoodProduct,
      where: fragment("? @> ?", p.countries, ^[country_tag]),
      order_by: [desc_nulls_last: p.completeness, asc: p.id],
      limit: ^Keyword.get(opts, :limit, 50),
      offset: ^Keyword.get(opts, :offset, 0)
    )
    |> Repo.all()
  end

  defp maybe_filter_country(query, nil), do: query

  defp maybe_filter_country(query, country_tag) do
    from p in query, where: fragment("? @> ?", p.countries, ^[country_tag])
  end

  @doc "Total number of products, optionally for one OFF country tag."
  def count_products(country_tag \\ nil) do
    FoodProduct
    |> maybe_filter_country(country_tag)
    |> Repo.aggregate(:count)
  end

  # ═════════════════════════════════════════════════════════════════════════
  # Upserts (shared by bulk import, delta sync, and API fallback)
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Upserts a batch of parsed products with their translations.

  `parsed` is a list of `{attrs, translations}` as returned by
  `ProductParser.parse_line/2`. Conflicts on `barcode` replace product data
  but never touch the ingredient link. Rows whose stored
  `off_last_modified_t` is newer than the incoming one are left as they are
  (delta files can arrive out of order).

  Returns the number of product rows written.
  """
  def upsert_products(parsed) when is_list(parsed) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      parsed
      |> Enum.map(fn {attrs, _translations} ->
        Map.merge(attrs, %{inserted_at: now, updated_at: now})
      end)
      # insert_all fails on duplicate conflict targets within one statement;
      # keep the freshest occurrence of each barcode.
      |> Enum.sort_by(&(&1.off_last_modified_t || 0))
      |> Map.new(&{&1.barcode, &1})
      |> Map.values()

    if rows == [] do
      0
    else
      {_count, returned} =
        Repo.insert_all(FoodProduct, rows,
          on_conflict: replace_if_not_stale(),
          conflict_target: :barcode,
          returning: [:id, :barcode]
        )

      barcode_to_id = Map.new(returned, &{&1.barcode, &1.id})
      upsert_translations(parsed, barcode_to_id, now)
      length(rows)
    end
  end

  # ON CONFLICT DO UPDATE, but only when the incoming row is at least as fresh
  # as the stored one. The ingredient link (ingredient_id / match score /
  # match status) is deliberately absent from the SET list — it belongs to the
  # matcher and manual review, never to imports. Stale rows are skipped by the
  # WHERE, so they don't come back in `returning` and their translations are
  # not touched either.
  defp replace_if_not_stale do
    from(p in FoodProduct,
      update: [
        set: [
          name: fragment("EXCLUDED.name"),
          brands: fragment("EXCLUDED.brands"),
          quantity: fragment("EXCLUDED.quantity"),
          countries: fragment("EXCLUDED.countries"),
          categories_tags: fragment("EXCLUDED.categories_tags"),
          nutriments: fragment("EXCLUDED.nutriments"),
          image_url: fragment("EXCLUDED.image_url"),
          image_small_url: fragment("EXCLUDED.image_small_url"),
          nutriscore_grade: fragment("EXCLUDED.nutriscore_grade"),
          ecoscore_grade: fragment("EXCLUDED.ecoscore_grade"),
          completeness: fragment("EXCLUDED.completeness"),
          off_last_modified_t: fragment("EXCLUDED.off_last_modified_t"),
          data_source: fragment("EXCLUDED.data_source"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ],
      where:
        is_nil(p.off_last_modified_t) or
          fragment("EXCLUDED.off_last_modified_t IS NULL") or
          p.off_last_modified_t <= fragment("EXCLUDED.off_last_modified_t")
    )
  end

  defp upsert_translations(parsed, barcode_to_id, now) do
    translation_rows =
      parsed
      |> Enum.flat_map(fn {attrs, translations} ->
        case barcode_to_id[attrs.barcode] do
          nil ->
            []

          product_id ->
            Enum.map(translations, fn t ->
              t
              |> Map.put(:food_product_id, product_id)
              |> Map.merge(%{inserted_at: now, updated_at: now})
            end)
        end
      end)
      |> Enum.uniq_by(&{&1.food_product_id, &1.language_name})

    if translation_rows != [] do
      Repo.insert_all(FoodProductTranslation, translation_rows,
        on_conflict: {:replace, [:name, :ingredients_text, :updated_at]},
        conflict_target: [:food_product_id, :language_name]
      )
    end
  end

  @doc """
  Language codes present in the `languages` table, as a `MapSet` for the
  parser's translation filter.
  """
  def known_language_codes do
    Languages.list_languages() |> MapSet.new(& &1.name)
  end

  # ═════════════════════════════════════════════════════════════════════════
  # Ingredient linking
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Links a product to an ingredient. `status` is `"auto"` (matcher) or
  `"manual"` (review UI); `score` is the similarity that produced the link.
  """
  def link_product_to_ingredient(%FoodProduct{} = product, ingredient_id, score, status)
      when status in ["auto", "manual"] do
    product
    |> FoodProduct.changeset(%{
      ingredient_id: ingredient_id,
      ingredient_match_score: score,
      ingredient_match_status: status
    })
    |> Repo.update()
  end

  @doc "Removes an ingredient link, marking the match as rejected."
  def unlink_product(%FoodProduct{} = product) do
    product
    |> FoodProduct.changeset(%{
      ingredient_id: nil,
      ingredient_match_score: nil,
      ingredient_match_status: "rejected"
    })
    |> Repo.update()
  end

  # ═════════════════════════════════════════════════════════════════════════
  # Sync state
  # ═════════════════════════════════════════════════════════════════════════

  @doc "Fetches the sync watermark row for `key` (e.g. \"delta\"), or nil."
  def get_sync_state(key) do
    Repo.get_by(SyncState, key: key)
  end

  @doc "Creates or updates the sync watermark row for `key`."
  def put_sync_state(key, attrs) do
    case get_sync_state(key) do
      nil -> %SyncState{key: key}
      state -> state
    end
    |> SyncState.changeset(Map.put(attrs, :key, key))
    |> Repo.insert_or_update()
  end

  defp off_client do
    Application.get_env(:mehungry, :off_client, Mehungry.OpenFoodFacts.Client)
  end
end
