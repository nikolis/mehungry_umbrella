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

  alias Mehungry.Repo

  alias Mehungry.Food.Enrichment
  alias Mehungry.Food.SpeciesFact

  @faostat_source %{
    source_type: "dataset",
    identifier: "faostat_qcl",
    title: "FAO FAOSTAT — Production: Crops and livestock products (QCL)",
    url: "https://www.fao.org/faostat/en/#data/QCL"
  }

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
        source: "external_db"
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
