defmodule Mehungry.FoodData.MyPlate.Client do
  @moduledoc """
  Client for the USDA MyPlate Kitchen recipe corpus, sourced from the **Internet
  Archive** (Wayback Machine) rather than the live myplate.food API.

  Why the Archive: the recipes are U.S. federal works in the **public domain**
  (17 USC §105). The original `myplate.gov` was retired on 2026-01-07. The
  myplate.food API mirrors them but caps full-recipe fetches at **100/day per IP**
  and forbids catalog replication without a license — a term of *its service*,
  separate from copyright. The Internet Archive merely *preserves* the original
  public-domain pages, so sourcing from it is "party to nobody's terms": no daily
  cap, no replication clause, and the original (not remastered) USDA images.

  Two moves, both over the Archive's public endpoints:

    * `list_slugs/0` — enumerate every archived `myplate.gov/recipes/{slug}` via
      the **CDX API**, filtered to base recipe URLs (no query variants). Cached.
    * `fetch_recipe/1` — resolve the closest pre-retirement capture via the
      **availability API**, fetch the raw archived HTML (`…/web/{ts}id_/…`), and
      extract the embedded schema.org **Recipe JSON-LD**, mapped into the same
      shape `FoodData.MyPlateImporter` already consumes
      (`%{"name", "yield", "ingredients" => [%{"text"}], "directions",
      "image_url", "source_url", "contributor", …}`).

  Behind `Mehungry.FoodData.MyPlate.ClientBehaviour`; the running app binds the
  `:myplate_client` config key to this module, tests bind a stub.
  """

  @behaviour Mehungry.FoodData.MyPlate.ClientBehaviour

  @cdx "https://web.archive.org/cdx/search/cdx"
  @web "https://web.archive.org/web"
  @recipe_base "https://www.myplate.gov/recipes"
  # Bias capture selection to a late pre-retirement snapshot (the site was retired
  # 2026-01-07; after that the live page 301s to realfood.gov).
  @capture_hint "20251215"

  # Longer Retry-After than this → treat as a hard throttle and fail fast rather
  # than block (the Archive is lenient, but be safe).
  @max_retry_after_s 30

  @slug_cache :recipes_cache
  @slug_cache_key :myplate_slug_list
  # The corpus is static; the CDX enumeration is a single large request. Cache it.
  @slug_cache_ttl :timer.hours(6)

  @doc "Returns the configured client module (this module in prod, a stub in tests)."
  def impl, do: Application.get_env(:mehungry, :myplate_client, __MODULE__)

  # ── slug enumeration ────────────────────────────────────────────────────────
  #
  # The corpus is static, and a live CDX wildcard enumeration takes ~50s (the
  # Archive scans every capture of every page variant). So the slug list ships as
  # a bundled manifest (`priv/myplate/slugs.json`) — just public-domain recipe
  # identifiers, not content — read instantly. CDX is the fallback if the manifest
  # is somehow missing, and `refresh_slugs/0` can regenerate the manifest.

  @slug_manifest "myplate/slugs.json"

  @impl true
  def list_slugs do
    case manifest_slugs() do
      slugs when is_list(slugs) and slugs != [] -> {:ok, slugs}
      _ -> cdx_slugs()
    end
  end

  @doc """
  Enumerates slugs live via the Internet Archive CDX API (slow, ~50s) and caches
  them — the fallback/refresh path behind the bundled `priv/myplate/slugs.json`
  manifest. Returns `{:ok, slugs}`.
  """
  def cdx_slugs do
    case cache_get(@slug_cache_key) do
      {:ok, slugs} when is_list(slugs) and slugs != [] ->
        {:ok, slugs}

      _ ->
        with {:ok, rows} <- request_json(cdx_url(), 120_000) do
          slugs = parse_cdx_slugs(rows)
          if slugs != [], do: cache_put(@slug_cache_key, slugs)
          {:ok, slugs}
        end
    end
  end

  defp manifest_slugs do
    path = Path.join(:code.priv_dir(:mehungry), @slug_manifest)

    with {:ok, body} <- File.read(path),
         {:ok, slugs} <- Jason.decode(body),
         true <- is_list(slugs) do
      slugs
    else
      _ -> nil
    end
  end

  defp cdx_url do
    "#{@cdx}?url=myplate.gov/recipes/*&output=json&fl=original" <>
      "&collapse=urlkey&filter=statuscode:200&filter=mimetype:text/html&limit=100000"
  end

  # CDX JSON is `[["original"], ["url"], ...]` (a header row then one url/row).
  # Keep only base recipe URLs (`/recipes/{slug}`, no query/fragment), dedup, sort.
  defp parse_cdx_slugs(rows) when is_list(rows) do
    rows
    |> Enum.drop(1)
    |> Enum.map(fn
      [url] when is_binary(url) -> url
      url when is_binary(url) -> url
      _ -> nil
    end)
    |> Enum.map(&slug_from_url/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_cdx_slugs(_), do: []

  defp slug_from_url(url) do
    case Regex.run(~r{^https?://(?:www\.)?myplate\.gov/recipes/([^/?#]+)/?$}, url) do
      [_, slug] -> slug
      _ -> nil
    end
  end

  # ── single recipe (raw capture → JSON-LD metadata + HTML body) ───────────────
  #
  # The USDA MyPlate JSON-LD Recipe node carries only metadata (name, yield,
  # image, nutrition, author) — the **ingredients and directions live in the Drupal
  # HTML body**, not the structured data. So we read metadata from the JSON-LD and
  # parse the ingredient/direction lists from the markup with Floki.

  @impl true
  def fetch_recipe(slug) when is_binary(slug) and slug != "" do
    original = "#{@recipe_base}/#{slug}"
    # Hit playback directly with the timestamp hint — Wayback redirects to the
    # closest capture (followed). This avoids the separate availability API, which
    # is throttled harder than playback and would double the request count.
    with {:ok, html} <- request_raw("#{@web}/#{@capture_hint}id_/#{original}"),
         {:ok, doc} <- Floki.parse_document(html) do
      {:ok, build_recipe(doc, html, original)}
    end
  end

  def fetch_recipe(_), do: {:error, :invalid_slug}

  defp build_recipe(doc, html, original) do
    meta = recipe_jsonld(html) || %{}

    %{
      "name" => meta["name"] || first_text(doc, "h1"),
      "yield" => to_yield(meta["recipeYield"]),
      "description" => clean_text(meta["description"]),
      "ingredients" => parse_ingredients(doc),
      "directions" => parse_directions(doc),
      # The JSON-LD image points at the original USDA CDN, which is dead
      # post-retirement (and the Wayback image proxy is unreliable), so we leave
      # it blank — `create_recipe/1` then queues an AI cover image. The admin can
      # also upload one in the review form.
      "image_url" => nil,
      "contributor" => to_author(meta["author"]),
      "source_url" => original,
      "recipe_url" => original
    }
  end

  # ── HTML body parsing (Floki) ────────────────────────────────────────────────

  # <ul class="… ingredients …"><li class="field__item"> TEXT
  #   <span class="notes">(note)</span></li>…</ul>
  defp parse_ingredients(doc) do
    doc
    |> Floki.find("ul.ingredients li.field__item")
    |> Enum.map(fn li ->
      note = li |> Floki.find("span.notes") |> Floki.text() |> clean_note()
      text = li |> Floki.filter_out("span.notes") |> Floki.text() |> clean_text()
      %{"text" => text, "note" => note}
    end)
    |> Enum.reject(&(&1["text"] in [nil, ""]))
  end

  # <div class="… field--name-field-instructions …"> … <ol><li>step</li>…</ol></div>
  # Joined into one directions paragraph (the importer re-splits into Step rows).
  defp parse_directions(doc) do
    case Floki.find(doc, ".field--name-field-instructions li") do
      [] ->
        doc |> Floki.find(".field--name-field-instructions .field__item") |> Floki.text() |> clean_text()

      items ->
        items
        |> Enum.map(&(&1 |> Floki.text() |> clean_text()))
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.map(&ensure_sentence_end/1)
        |> Enum.join(" ")
    end
  end

  defp first_text(doc, selector) do
    case doc |> Floki.find(selector) |> Floki.text() |> clean_text() do
      "" -> nil
      text -> text
    end
  end

  # "(or cooking oil of your choice)" → "or cooking oil of your choice"
  defp clean_note(""), do: nil

  defp clean_note(text) do
    text |> clean_text() |> String.trim_leading("(") |> String.trim_trailing(")") |> blank_to_nil()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  # ── JSON-LD metadata ─────────────────────────────────────────────────────────

  # First <script type="application/ld+json"> that is (or contains, via @graph/
  # list) a schema.org Recipe node; nil if none.
  defp recipe_jsonld(html) do
    ~r{<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}si
    |> Regex.scan(html)
    |> Enum.find_value(nil, fn [_, json] ->
      with {:ok, decoded} <- Jason.decode(json) do
        recipe_node(decoded)
      else
        _ -> nil
      end
    end)
  end

  defp recipe_node(%{"@graph" => graph}) when is_list(graph), do: Enum.find(graph, &recipe?/1)
  defp recipe_node(list) when is_list(list), do: Enum.find(list, &recipe?/1)
  defp recipe_node(map) when is_map(map), do: if(recipe?(map), do: map, else: nil)
  defp recipe_node(_), do: nil

  defp recipe?(%{"@type" => type}), do: type == "Recipe" or (is_list(type) and "Recipe" in type)
  defp recipe?(_), do: false

  defp ensure_sentence_end(s) do
    if String.match?(s, ~r/[.!?]$/), do: s, else: s <> "."
  end

  defp to_author(%{"name" => name}), do: to_author(name)
  defp to_author(name) when is_binary(name), do: name
  defp to_author([first | _]), do: to_author(first)
  defp to_author(_), do: nil

  defp to_yield(v) when is_integer(v), do: "#{v} servings"
  defp to_yield([h | _]), do: to_yield(h)
  defp to_yield(v) when is_binary(v), do: v
  defp to_yield(_), do: nil

  # JSON-LD text can carry HTML entities / stray whitespace; normalize lightly.
  defp clean_text(nil), do: nil

  defp clean_text(text) when is_binary(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&#39;", "'")
    |> String.replace("&quot;", "\"")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clean_text(other), do: other

  # ── caching ─────────────────────────────────────────────────────────────────

  defp cache_get(key) do
    Cachex.get(@slug_cache, key)
  rescue
    _ -> {:ok, nil}
  end

  defp cache_put(key, value) do
    Cachex.put(@slug_cache, key, value, ttl: @slug_cache_ttl)
  rescue
    _ -> :ok
  end

  # ── HTTP ──────────────────────────────────────────────────────────────────

  defp request_json(url, timeout) do
    with {:ok, body} <- request(url, timeout, 3), do: Jason.decode(body)
  end

  defp request_raw(url), do: request(url, 30_000, 3)

  # Retry transient failures — network errors, 5xx, and short 429 throttles — with
  # backoff. A long Retry-After is surfaced as {:error, {:rate_limited, seconds}}
  # (the LiveView explains it) rather than blocking. Archive playback uses
  # same-host redirects, so follow them.
  defp request(url, timeout, attempts) do
    case HTTPoison.get(url, [], recv_timeout: timeout, follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 429, headers: headers}} ->
        seconds = retry_after_seconds(headers)

        cond do
          seconds > @max_retry_after_s -> {:error, {:rate_limited, seconds}}
          attempts > 1 -> Process.sleep(seconds * 1000 + 200); request(url, timeout, attempts - 1)
          true -> {:error, {:rate_limited, seconds}}
        end

      {:ok, %HTTPoison.Response{status_code: status}} when status >= 500 and attempts > 1 ->
        Process.sleep(backoff_ms(attempts))
        request(url, timeout, attempts - 1)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{}} when attempts > 1 ->
        Process.sleep(backoff_ms(attempts))
        request(url, timeout, attempts - 1)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp backoff_ms(attempts), do: (4 - attempts) * 600

  defp retry_after_seconds(headers) do
    header =
      Enum.find_value(headers, fn {k, v} ->
        if String.downcase(k) == "retry-after", do: v
      end)

    case header && Integer.parse(header) do
      {seconds, _} when seconds > 0 -> seconds
      _ -> 5
    end
  end
end
