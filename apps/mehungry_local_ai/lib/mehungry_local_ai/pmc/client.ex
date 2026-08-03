defmodule MehungryLocalAi.PMC.Client do
  @moduledoc """
  NCBI PMC open-access full-text client. Two calls:

    * `resolve_pmcid/1` — PMID → PMCID via the id-converter API.
    * `fetch_fulltext/1` — PMCID → JATS XML via E-utilities `efetch db=pmc`.

  The HTTP call resolves through the `:pmc_http_adapter` app-env seam (defaults to
  `&HTTPoison.get/3`) so tests run without a network round-trip. Since the mix task
  is serial and low-volume, a fixed `Process.sleep` pace before each call keeps us
  under NCBI's ~3 req/s courtesy limit (no shared Cachex budget needed).
  """

  # NCBI migrated PMC off www.ncbi.nlm.nih.gov in 2024; the old
  # /pmc/utils/idconv/v1.0/ path now 301-redirects here (HTTPoison does not follow
  # redirects, so the stale URL surfaced as {:http, 301} on every call). Same JSON shape.
  @idconv "https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/"
  @efetch "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
  @timeout_ms 30_000
  @pace_ms 350

  @doc "Resolve a PMID to its PMCID (`\"PMC1234567\"`), or `{:error, :no_pmcid}`."
  def resolve_pmcid(pmid) do
    params = URI.encode_query(ids: to_string(pmid), format: "json", tool: "mehungry")

    with {:ok, body} <- get(@idconv <> "?" <> params),
         {:ok, decoded} <- Jason.decode(body) do
      case decoded do
        %{"records" => [%{"pmcid" => pmcid} | _]} when is_binary(pmcid) and pmcid != "" ->
          {:ok, pmcid}

        _ ->
          {:error, :no_pmcid}
      end
    end
  end

  @doc "Fetch the JATS XML full text for a PMCID (empty/non-OA bodies are the caller's concern)."
  def fetch_fulltext(pmcid) do
    id = String.replace_prefix(pmcid, "PMC", "")
    params = URI.encode_query(db: "pmc", id: id, rettype: "xml", retmode: "xml", tool: "mehungry")
    get(@efetch <> "?" <> params)
  end

  # ── HTTP + local pacing ─────────────────────────────────────────────────────

  defp get(url) do
    Process.sleep(@pace_ms)
    do_get(url)
  end

  defp do_get(url) do
    case adapter().(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: 404}} -> {:error, :not_found}
      {:ok, %{status_code: code}} when code in [429, 503] -> {:error, {:rate_limited, 30}}
      {:ok, %{status_code: code}} -> {:error, {:http, code}}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, {:network, reason}}
      other -> {:error, other}
    end
  end

  defp adapter, do: Application.get_env(:mehungry_local_ai, :pmc_http_adapter, &HTTPoison.get/3)
end
