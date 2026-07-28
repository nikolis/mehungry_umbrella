defmodule Mehungry.Food.IdentityResolution.ExternalScientificIdClient do
  @moduledoc """
  Live `ScientificIdClient` — resolves a scientific name to external identifiers
  via public, key-free APIs:

    * **Wikidata** — `wbsearchentities` maps the name to a Q-id (`wikidata_id`),
      then the entity's claims give the **NCBI Taxonomy ID** (property `P685`) and
      its English aliases become common-name synonyms.
    * **EBI OLS4** — the Ontology Lookup Service search resolves the name to a
      **FoodOn** term (`foodon_id`).

  Every sub-lookup is best-effort and defensive: network/parse failures are
  swallowed and the partial result is still returned, so external-API flakiness
  never fails a resolution batch. HTTP goes through the `:identity_http_adapter`
  app-env seam (defaults to `&HTTPoison.get/3`) so tests run offline.
  """

  @behaviour Mehungry.Food.IdentityResolution.ScientificIdClient

  require Logger

  @wikidata_api "https://www.wikidata.org/w/api.php"
  @wikidata_entity "https://www.wikidata.org/wiki/Special:EntityData"
  @ols_search "https://www.ebi.ac.uk/ols4/api/search"
  # Wikidata property for "NCBI taxonomy ID".
  @ncbi_property "P685"
  @timeout_ms 12_000
  @user_agent "Mehungry/1.0 (ingredient identity resolution)"

  @impl true
  def resolve(scientific_name) when is_binary(scientific_name) do
    wikidata = resolve_wikidata(scientific_name)
    foodon_id = resolve_foodon(scientific_name)

    ids =
      wikidata
      |> Map.put(:foodon_id, foodon_id)
      |> put_id_source()

    {:ok, ids}
  rescue
    error ->
      Logger.warning("[IdentityResolution] external id lookup crashed: #{inspect(error)}")
      {:ok, %{}}
  end

  # ── Wikidata: Q-id, NCBI taxid (P685), alias synonyms ────────────────────

  defp resolve_wikidata(name) do
    with {:ok, qid} <- wikidata_search(name),
         {:ok, entity} <- wikidata_entity(qid) do
      %{
        wikidata_id: qid,
        ncbi_taxonomy_id: ncbi_from_entity(entity, qid),
        synonyms: synonyms_from_entity(entity, qid)
      }
    else
      _ -> %{}
    end
  end

  defp wikidata_search(name) do
    params =
      URI.encode_query(%{
        action: "wbsearchentities",
        search: name,
        language: "en",
        type: "item",
        format: "json",
        limit: 1
      })

    case get_json("#{@wikidata_api}?#{params}") do
      {:ok, %{"search" => [%{"id" => qid} | _]}} -> {:ok, qid}
      _ -> :error
    end
  end

  defp wikidata_entity(qid) do
    case get_json("#{@wikidata_entity}/#{qid}.json") do
      {:ok, %{"entities" => %{^qid => entity}}} -> {:ok, entity}
      _ -> :error
    end
  end

  defp ncbi_from_entity(entity, _qid) do
    with %{"claims" => %{@ncbi_property => [claim | _]}} <- entity,
         %{"mainsnak" => %{"datavalue" => %{"value" => value}}} <- claim,
         {int, _} <- Integer.parse(to_string(value)) do
      int
    else
      _ -> nil
    end
  end

  defp synonyms_from_entity(entity, _qid) do
    case entity do
      %{"aliases" => %{"en" => aliases}} when is_list(aliases) ->
        for %{"value" => value} <- aliases, is_binary(value) do
          %{name: value, synonym_type: "common_name", source: "wikidata"}
        end

      _ ->
        []
    end
  end

  # ── EBI OLS4: FoodOn id ──────────────────────────────────────────────────

  defp resolve_foodon(name) do
    params = URI.encode_query(%{q: name, ontology: "foodon", rows: 1})

    case get_json("#{@ols_search}?#{params}") do
      {:ok, %{"response" => %{"docs" => [%{"obo_id" => obo_id} | _]}}} when is_binary(obo_id) ->
        obo_id

      _ ->
        nil
    end
  end

  # ── provenance + HTTP ────────────────────────────────────────────────────

  # Tag where the identifiers came from: Wikidata is primary; fall back to OLS
  # when only FoodOn was found.
  defp put_id_source(%{wikidata_id: qid} = ids) when is_binary(qid),
    do: Map.put(ids, :id_source, "wikidata")

  defp put_id_source(%{foodon_id: id} = ids) when is_binary(id),
    do: Map.put(ids, :id_source, "ols")

  defp put_id_source(ids), do: ids

  defp get_json(url) do
    headers = [{"User-Agent", @user_agent}, {"Accept", "application/json"}]

    case adapter().(url, headers, recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} -> Jason.decode(body)
      {:ok, %{status_code: code}} -> {:error, {:http, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp adapter, do: Application.get_env(:mehungry, :identity_http_adapter, &HTTPoison.get/3)
end
