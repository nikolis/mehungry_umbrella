defmodule Mehungry.FoodData.Wikidata.Client do
  @moduledoc """
  Live Wikidata enrichment fetch (see `docs/implementation/science/species_enrichment.md`).

  Wikidata content is **CC0** (public domain) — the safest enrichment source and the
  reason it leads. Resolves a species to a Q-id via `wbsearchentities`, reads the
  entity's short descriptions (en/el), Wikipedia sitelinks (en/el), and an **origin
  region** from the first present of `P495` (country of origin), `P2341` (indigenous
  to), `P183` (endemic to) — the referenced item's label resolved with one extra
  `wbgetentities` labels call.

  Mirrors `Food.IdentityResolution.ExternalScientificIdClient`'s discipline: key-free
  public API, defensive parse (a failure yields `{:ok, %{}}`), HTTP behind the
  `:wikidata_http_adapter` app-env seam so parsing is unit-testable offline. The module
  itself sits behind `Mehungry.FoodData.Wikidata.ClientBehaviour` (`:wikidata_client`
  key) so the whole fetch can be stubbed.
  """

  @behaviour Mehungry.FoodData.Wikidata.ClientBehaviour

  require Logger

  @api "https://www.wikidata.org/w/api.php"
  @entity "https://www.wikidata.org/wiki/Special:EntityData"
  # Origin properties, tried in order; first present wins.
  @origin_properties ~w(P495 P2341 P183)
  @locales ~w(en el)
  @timeout_ms 12_000
  @user_agent "Mehungry/1.0 (species enrichment; +https://www.m3hungry.com)"

  @doc "The configured client module (this module in prod, a stub in tests)."
  def impl, do: Application.get_env(:mehungry, :wikidata_client, __MODULE__)

  @impl true
  def fetch(name, scientific_name \\ nil) do
    with {:ok, qid} <- resolve_qid(scientific_name, name),
         {:ok, entity} <- fetch_entity(qid) do
      {:ok,
       %{
         qid: qid,
         descriptions: localized_values(entity, "descriptions"),
         wikipedia_urls: wikipedia_urls(entity),
         origin_region: origin_region(entity)
       }
       |> prune()}
    else
      _ -> {:ok, %{}}
    end
  rescue
    error ->
      Logger.warning("[Wikidata] enrichment fetch crashed: #{inspect(error)}")
      {:ok, %{}}
  end

  # ── Q-id resolution (scientific name first, then common name) ──────────────────

  defp resolve_qid(scientific_name, name) do
    case search(scientific_name) do
      {:ok, qid} -> {:ok, qid}
      _ -> search(name)
    end
  end

  defp search(term) when is_binary(term) and term != "" do
    params =
      URI.encode_query(%{
        action: "wbsearchentities",
        search: term,
        language: "en",
        type: "item",
        format: "json",
        limit: 1
      })

    case get_json("#{@api}?#{params}") do
      {:ok, %{"search" => [%{"id" => qid} | _]}} -> {:ok, qid}
      _ -> :error
    end
  end

  defp search(_), do: :error

  defp fetch_entity(qid) do
    case get_json("#{@entity}/#{qid}.json") do
      {:ok, %{"entities" => %{^qid => entity}}} -> {:ok, entity}
      _ -> :error
    end
  end

  # ── Field extraction ──────────────────────────────────────────────────────────

  # descriptions/labels → %{"en" => value, "el" => value} (present locales only).
  defp localized_values(entity, key) do
    for locale <- @locales,
        value = get_in(entity, [key, locale, "value"]),
        is_binary(value),
        into: %{},
        do: {locale, value}
  end

  defp wikipedia_urls(entity) do
    for locale <- @locales,
        link = get_in(entity, ["sitelinks", "#{locale}wiki"]),
        url = sitelink_url(link, locale),
        is_binary(url),
        into: %{},
        do: {locale, url}
  end

  defp sitelink_url(%{"url" => url}, _locale) when is_binary(url), do: url

  defp sitelink_url(%{"title" => title}, locale) when is_binary(title),
    do: "https://#{locale}.wikipedia.org/wiki/#{URI.encode(String.replace(title, " ", "_"))}"

  defp sitelink_url(_, _), do: nil

  # First present origin property → the referenced item's English label.
  defp origin_region(entity) do
    claims = Map.get(entity, "claims", %{})

    Enum.find_value(@origin_properties, fn prop ->
      with [claim | _] <- Map.get(claims, prop),
           qid when is_binary(qid) <- origin_target_qid(claim),
           label when is_binary(label) <- item_label(qid) do
        label
      else
        _ -> nil
      end
    end)
  end

  defp origin_target_qid(claim) do
    case get_in(claim, ["mainsnak", "datavalue", "value", "id"]) do
      qid when is_binary(qid) -> qid
      _ -> nil
    end
  end

  defp item_label(qid) do
    params =
      URI.encode_query(%{
        action: "wbgetentities",
        ids: qid,
        props: "labels",
        languages: "en",
        format: "json"
      })

    case get_json("#{@api}?#{params}") do
      {:ok, body} -> get_in(body, ["entities", qid, "labels", "en", "value"])
      _ -> nil
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  # Drop empty maps/nils so the caller only records facts that are actually present.
  defp prune(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == %{} end)
    |> Map.new()
  end

  defp get_json(url) do
    headers = [{"User-Agent", @user_agent}, {"Accept", "application/json"}]

    case adapter().(url, headers, recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} -> Jason.decode(body)
      {:ok, %{status_code: code}} -> {:error, {:http, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp adapter, do: Application.get_env(:mehungry, :wikidata_http_adapter, &HTTPoison.get/3)
end
