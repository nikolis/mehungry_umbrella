defmodule Mehungry.Food.SpeciesEnrichment do
  @moduledoc """
  Review-gated enrichment facts for a `FoundementalFoodSpecies` — the provenance-cited
  "interesting info" surfaced in the /foods "Origins & cultivation" section
  (see `docs/implementation/science/species_enrichment.md`).

  Two external sources, both fanned into `SpeciesFact` rows staged
  `pending → promoted | rejected`:

    * **Wikidata** (CC0) — origin region, a short description, a Wikipedia link.
    * **FAOSTAT** (CC BY 4.0, attribution required) — top producing countries.

  Nothing surfaces until an admin promotes it at `/professional/species-enrichment`:
  external identity-matching (a Wikidata top-hit for an ambiguous name) can be wrong.
  Provenance reuses the shared `IngredientEnrichmentSource` citation registry via
  `Food.Enrichment.upsert_enrichment_source/1`.

  Public functions are exposed on the `Mehungry.Food` facade under `*_species_fact(s)`
  names.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Storage

  alias Mehungry.Food.Enrichment
  alias Mehungry.Food.FoundementalFoods
  alias Mehungry.Food.SpeciesFact
  alias Mehungry.FoodData.Faostat
  alias Mehungry.FoodData.Wikidata
  alias Mehungry.FoodData.Wikidata.ImageLicense

  @faostat_source %{
    source_type: "dataset",
    identifier: "faostat_qcl",
    title: "FAO FAOSTAT — Production: Crops and livestock products (QCL)",
    url: "https://www.fao.org/faostat/en/#data/QCL"
  }

  # Be polite to the Wikidata API between species.
  @wikidata_pause_ms 250

  # Re-hosting the licence-gated Commons lead image.
  @image_user_agent "Mehungry/1.0 (species images; +https://www.m3hungry.com)"
  @image_timeout_ms 20_000

  # ── Fetch orchestration (one species) ─────────────────────────────────────────

  @doc """
  Fetch + record enrichment facts for **one** species, returning
  `%{wikidata: n, faostat: m}` (facts upserted per source). Shared by
  `mix species.enrich` and `Mehungry.ObanWorkers.SpeciesEnrichmentWorker`.

  Options:

    * `:source` — `"all"` (default) | `"wikidata"` | `"faostat"`.
    * `:faostat_rows` — pre-loaded FAOSTAT rows (`Faostat.Client.load_rows/0` shape) to
      avoid re-reading the bundled CSV per call in a batch; loaded (24h-cached) on demand
      when absent.

  FAOSTAT facts are **auto-promoted** (low mismatch risk — keyed on a curated item code);
  Wikidata facts stay `pending` for review (ambiguous-name top-hit can be wrong).
  """
  def enrich_species(%{id: id} = species, opts \\ []) when is_integer(id) do
    source = Keyword.get(opts, :source, "all")

    wikidata = if source in ["all", "wikidata"], do: enrich_wikidata(species), else: 0
    faostat = if source in ["all", "faostat"], do: enrich_faostat(species, opts), else: 0

    %{wikidata: wikidata, faostat: faostat}
  end

  defp enrich_wikidata(species) do
    {:ok, result} = Wikidata.Client.impl().fetch(species.name, species.scientific_name)
    count = record_wikidata_facts(species.id, result)
    # Re-host the lead image (same fetch result → no extra Q-id lookup) when its
    # Commons licence is reusable. Best-effort: a failure leaves the emoji fallback.
    maybe_store_species_image(species, result[:image])
    Process.sleep(@wikidata_pause_ms)
    count
  end

  defp enrich_faostat(%{faostat_item_code: nil}, _opts), do: 0

  defp enrich_faostat(%{faostat_item_code: code} = species, opts) do
    rows = Keyword.get_lazy(opts, :faostat_rows, &load_faostat_rows/0)
    producers = Faostat.Parser.top_producers(rows, code)
    record_faostat_facts(species.id, producers)
  end

  # ── Lead image (licence-gated Commons photo) ──────────────────────────────────

  defp maybe_store_species_image(_species, nil), do: :ok

  defp maybe_store_species_image(species, image) when is_map(image) do
    cond do
      not ImageLicense.reusable?(image) ->
        :ok

      already_stored?(species, image) ->
        :ok

      true ->
        store_species_image(species, image)
    end
  end

  # Skip the re-download when we already hold this exact Commons file.
  defp already_stored?(%{image_url: url, image_source_url: src}, image)
       when is_binary(url) and url != "",
       do: src == image[:descriptionurl]

  defp already_stored?(_species, _image), do: false

  defp store_species_image(species, image) do
    {ext, content_type} = image_content_type(image[:url])

    with {:ok, binary} <- download_image(image[:url]),
         key = "species_images/#{species.id}.#{ext}",
         {:ok, %{url: url}} <- Storage.put(key, binary, content_type: content_type),
         {:ok, _} <- FoundementalFoods.update_species(species, image_attrs(image, url)) do
      :ok
    else
      error ->
        Logger.warning(
          "[SpeciesEnrichment] species ##{species.id} image skipped: #{inspect(error)}"
        )

        :ok
    end
  end

  defp image_attrs(image, stored_url) do
    %{
      image_url: stored_url,
      image_license: image[:license_name],
      image_license_url: image[:license_url],
      # The author alone — surfaces compose the full "artist · licence · Commons"
      # credit from the separate columns (and the API via `attribution_text/1`).
      image_attribution: image[:artist],
      image_source_url: image[:descriptionurl]
    }
  end

  defp download_image(url) when is_binary(url) do
    headers = [{"User-Agent", @image_user_agent}]
    opts = [recv_timeout: @image_timeout_ms, follow_redirect: true]

    case image_adapter().(url, headers, opts) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: code}} -> {:error, {:http, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp download_image(_), do: {:error, :no_url}

  # HTTP seam for the image download, stubbable in tests (mirrors the Wikidata client).
  defp image_adapter,
    do: Application.get_env(:mehungry, :species_image_http_adapter, &HTTPoison.get/3)

  defp image_content_type(url) do
    base = url |> to_string() |> String.downcase() |> String.split("?") |> hd()

    cond do
      String.ends_with?(base, ".png") -> {"png", "image/png"}
      String.ends_with?(base, ".webp") -> {"webp", "image/webp"}
      true -> {"jpg", "image/jpeg"}
    end
  end

  @doc "Load the bundled FAOSTAT production rows (24h-cached), or `[]` on failure."
  def load_faostat_rows do
    case Faostat.Client.impl().load_rows() do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  @doc """
  FAOSTAT crosswalk suggestions for a list of species — a map
  `%{species_id => %{code: ..., item: ..., score: ...} | nil}` giving each species'
  best fuzzy name→item match (via `Faostat.Parser.suggest_item_code/2`). The bundled
  item list is loaded once. Returns `%{}` when the CSV is unreadable. Read-only — a
  curation aid for the admin crosswalk UI (mirrors `mix species.faostat_crosswalk`);
  it never writes a code.
  """
  def suggest_faostat_codes(species) when is_list(species) do
    case Faostat.Parser.items(load_faostat_rows()) do
      [] ->
        %{}

      items ->
        Map.new(species, fn %{id: id, name: name} ->
          suggestion =
            case Faostat.Parser.suggest_item_code(name, items) do
              {code, item, score} -> %{code: code, item: item, score: score}
              _ -> nil
            end

          {id, suggestion}
        end)
    end
  end

  # ── Fetch intake (fan a fetch result into pending facts) ──────────────────────

  @doc """
  Record the Wikidata facts fetched for a species. `result` is the
  `FoodData.Wikidata.Client` shape: `%{qid: "Q89", origin_region: "Central Asia",
  descriptions: %{"en" => "...", "el" => "..."}, wikipedia_urls: %{"en" => url,
  "el" => url}}` (any key may be absent). Returns the number of facts upserted.
  """
  def record_wikidata_facts(species_id, result) when is_integer(species_id) and is_map(result) do
    source = wikidata_source(result)
    base = %{foundemental_species_id: species_id, enrichment_source_id: source && source.id}

    facts =
      wikidata_fact_attrs(result)
      |> Enum.map(&Map.merge(base, &1))

    Enum.reduce(facts, 0, fn attrs, count ->
      {:ok, _} = upsert_fact(attrs)
      count + 1
    end)
  end

  @doc """
  Record the FAOSTAT top-producers fact for a species. `producers` is a list of
  `%{country: "China", tonnes: 123.0, year: 2022}` maps (already ranked). Stores one
  `top_producers` fact carrying the list in `value_json`. Returns the number upserted
  (0 or 1).
  """
  def record_faostat_facts(_species_id, []), do: 0

  def record_faostat_facts(species_id, producers)
      when is_integer(species_id) and is_list(producers) do
    {:ok, source} = Enrichment.upsert_enrichment_source(stamp(@faostat_source))

    {:ok, _} =
      upsert_fact(%{
        foundemental_species_id: species_id,
        enrichment_source_id: source.id,
        fact_key: "top_producers",
        locale: "",
        value_json: %{"producers" => producers},
        value_text: producers |> Enum.map(& &1[:country]) |> Enum.join(", "),
        source: "external_db",
        # Auto-promote FAOSTAT: keyed on a curated item code, so no identity-mismatch
        # risk. `upsert_fact/1`'s on-conflict never touches `:status`, so a previously
        # rejected fact stays rejected and a re-fetch won't flip an already-set status.
        status: "promoted"
      })

    1
  end

  # Build the Wikidata citation (one `url` source per Q-id). Nil when the fetch had no
  # Q-id (facts then carry no source — still reviewable, just uncited).
  defp wikidata_source(%{qid: qid}) when is_binary(qid) and qid != "" do
    {:ok, source} =
      Enrichment.upsert_enrichment_source(
        stamp(%{
          source_type: "url",
          identifier: qid,
          title: "Wikidata #{qid}",
          url: "https://www.wikidata.org/wiki/#{qid}"
        })
      )

    source
  end

  defp wikidata_source(_), do: nil

  # Flatten a Wikidata fetch result into `SpeciesFact` attr maps (one per fact/locale).
  defp wikidata_fact_attrs(result) do
    origin =
      case result[:origin_region] do
        region when is_binary(region) and region != "" ->
          [%{fact_key: "origin_region", locale: "", value_text: region, source: "external_db"}]

        _ ->
          []
      end

    descriptions = locale_facts("description", result[:descriptions])
    wikipedia = locale_facts("wikipedia_url", result[:wikipedia_urls])

    origin ++ descriptions ++ wikipedia
  end

  defp locale_facts(_key, nil), do: []

  defp locale_facts(fact_key, map) when is_map(map) do
    for {locale, value} <- map, is_binary(value) and value != "" do
      %{fact_key: fact_key, locale: locale, value_text: value, source: "external_db"}
    end
  end

  @doc "Upsert one fact, refreshing only extraction fields (never `status`)."
  def upsert_fact(attrs) do
    %SpeciesFact{}
    |> SpeciesFact.changeset(Map.put_new(attrs, :retrieved_at, now()))
    |> Repo.insert(
      on_conflict:
        {:replace, [:value_text, :value_json, :confidence, :enrichment_source_id, :retrieved_at, :updated_at]},
      conflict_target: [:foundemental_species_id, :fact_key, :locale, :source],
      returning: true
    )
  end

  # ── Promotion / review ────────────────────────────────────────────────────────

  @doc "Promote a fact (it now surfaces). Accepts a struct or id."
  def promote_fact(%SpeciesFact{} = fact), do: set_status(fact, "promoted")
  def promote_fact(id) when is_integer(id), do: promote_fact(get_fact!(id))

  @doc "Reject a fact (sticky — a re-fetch won't resurrect it). Accepts a struct or id."
  def reject_fact(%SpeciesFact{} = fact), do: set_status(fact, "rejected")
  def reject_fact(id) when is_integer(id), do: reject_fact(get_fact!(id))

  @doc "Manually edit a fact's value (and re-stamp it `pending`)."
  def update_fact_value(%SpeciesFact{} = fact, value_text) do
    fact |> SpeciesFact.changeset(%{value_text: value_text}) |> Repo.update()
  end

  defp set_status(%SpeciesFact{} = fact, status),
    do: fact |> SpeciesFact.changeset(%{status: status}) |> Repo.update()

  @doc "Promote every pending fact in one shot. Returns the number promoted."
  def promote_all_pending_facts do
    {count, _} =
      from(f in SpeciesFact, where: f.status == "pending")
      |> Repo.update_all(set: [status: "promoted", updated_at: now()])

    count
  end

  # ── Queries ───────────────────────────────────────────────────────────────────

  @doc "Pending facts for review, newest first; paged. Preloads species + source."
  def list_pending_facts(opts \\ []), do: list_by_status("pending", opts)

  @doc "Promoted facts (curated), newest first; paged."
  def list_promoted_facts(opts \\ []), do: list_by_status("promoted", opts)

  defp list_by_status(status, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(f in SpeciesFact,
        where: f.status == ^status,
        order_by: [asc: f.foundemental_species_id, asc: f.fact_key, asc: f.locale],
        preload: [:species, :enrichment_source],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  def get_fact!(id), do: Repo.get!(SpeciesFact, id) |> Repo.preload([:species, :enrichment_source])

  def count_pending_facts, do: count_by_status("pending")
  def count_promoted_facts, do: count_by_status("promoted")

  defp count_by_status(status),
    do: Repo.aggregate(from(f in SpeciesFact, where: f.status == ^status), :count, :id)

  @doc """
  Promoted facts for a species, ready to surface — locale-resolved to `locale`
  (locale-independent facts carry `""` and always match). Preloads the citation.
  Returns a map keyed by `fact_key` → the single best fact (requested locale wins over
  `"en"` fallback), so the caller renders `facts[:origin_region]` etc. directly.
  """
  def promoted_facts_for_species(species_id, locale \\ "en") when is_integer(species_id) do
    Repo.all(
      from(f in SpeciesFact,
        where:
          f.foundemental_species_id == ^species_id and f.status == "promoted" and
            f.locale in ^Enum.uniq([locale, "en", ""]),
        preload: [:enrichment_source]
      )
    )
    |> Enum.group_by(& &1.fact_key)
    |> Map.new(fn {key, facts} -> {key, best_locale(facts, locale)} end)
  end

  # Prefer the requested locale, then English, then the locale-independent/first row.
  defp best_locale(facts, locale) do
    Enum.find(facts, &(&1.locale == locale)) ||
      Enum.find(facts, &(&1.locale == "en")) ||
      hd(facts)
  end

  defp stamp(attrs), do: Map.put(attrs, :retrieved_at, now())
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
