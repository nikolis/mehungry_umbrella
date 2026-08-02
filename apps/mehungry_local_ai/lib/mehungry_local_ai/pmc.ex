defmodule MehungryLocalAi.PMC do
  @moduledoc """
  Orchestrates PMC open-access full-text retrieval for one study: resolve the PMCID,
  fetch + parse the JATS full text, and return the outcome for the caller to post
  back to the server. Most papers are not open-access, so most calls return a skip
  (`no_pmcid` / `not_oa`).

  A transient failure (rate-limit / network) is returned as `{:error, reason}` so the
  mix task can skip/retry — nothing is ledgered on the server, keeping retries idempotent.
  """

  require Logger

  alias MehungryLocalAi.PMC.{Client, Parser}

  # Below this many bytes of body text we treat the record as not usefully OA.
  @min_body 200

  @type result :: %{pmcid: String.t() | nil, source: String.t() | nil, body: String.t() | nil, outcome: String.t()}

  @spec fetch(integer()) :: {:ok, result()} | {:error, term()}
  def fetch(pmid) when is_integer(pmid) do
    case Client.resolve_pmcid(pmid) do
      {:ok, pmcid} ->
        fetch_body(pmcid)

      {:error, :no_pmcid} ->
        {:ok, skip(nil, "no_pmcid")}

      {:error, {kind, _} = reason} when kind in [:rate_limited, :network] ->
        {:error, reason}

      {:error, reason} ->
        Logger.warning("PMC idconv failed for pmid #{pmid}: #{inspect(reason)}")
        {:ok, skip(nil, "error")}
    end
  end

  def fetch(_), do: {:ok, skip(nil, "no_pmcid")}

  defp fetch_body(pmcid) do
    case Client.fetch_fulltext(pmcid) do
      {:ok, xml} ->
        case Parser.to_text(xml) do
          text when byte_size(text) >= @min_body ->
            {:ok, %{pmcid: pmcid, source: "pmc_oa", body: text, outcome: "open_access"}}

          _ ->
            {:ok, skip(pmcid, "not_oa")}
        end

      {:error, :not_found} ->
        {:ok, skip(pmcid, "not_oa")}

      {:error, {kind, _} = reason} when kind in [:rate_limited, :network] ->
        {:error, reason}

      {:error, reason} ->
        Logger.warning("PMC efetch failed for #{pmcid}: #{inspect(reason)}")
        {:ok, skip(pmcid, "error")}
    end
  end

  defp skip(pmcid, outcome), do: %{pmcid: pmcid, source: nil, body: nil, outcome: outcome}
end
