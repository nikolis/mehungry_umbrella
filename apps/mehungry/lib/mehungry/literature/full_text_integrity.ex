defmodule Mehungry.Literature.FullTextIntegrity do
  @moduledoc """
  Verify that a stored `StudyFullText` body actually belongs to its cited paper —
  **by provenance, not by text**.

  The extractor historically did a loose PMID→PMCID `elink` and, when the real full
  text wasn't in PMC, stored a **different but topically-related** article's text under
  the correct citation (an `elink` *neighbor*). Because the substitute is a related
  paper, it shares the cited paper's vocabulary — so a text-overlap check cannot tell
  them apart (empirically, a confirmed-mismatched paper scored 0.74 abstract/body
  containment, and every paper's distinctive title terms appear in its body). Text is
  not a usable signal here.

  The reliable signal is **PMC Open Access subset membership**. A paper that is
  genuinely in the OA subset has its *own* PMCID, so the old extractor fetched the
  right article; one that is not in the OA subset could only have been populated by a
  neighbor substitution. We confirm membership (and read the real license) per-PMID via
  Europe PMC, behind the `:europepmc_client` seam.

      verdict = verify(pmid) |> classify()
      #=> :verified | :mismatch | :pending_review

    * `:verified`    — in the OA subset; body is the real paper. Display is then gated
      separately by license (`Mehungry.Literature.License.reusable?/1`).
    * `:mismatch`    — not in the OA subset and no reuse license at all: the stored body
      is an unverifiable substitute. Purge it.
    * `:pending_review` — ambiguous (lookup inconclusive, or a CC-licensed paper that
      Europe PMC does not currently flag as OA). A human decides via the admin queue.
  """

  require Logger

  alias Mehungry.Literature.License

  @type verification :: %{
          found?: boolean(),
          oa?: boolean(),
          license: String.t(),
          license_url: String.t() | nil,
          pmcid: String.t() | nil
        }

  @doc "The Europe PMC client (overridable in tests via `:europepmc_client`)."
  def client do
    Application.get_env(:mehungry, :europepmc_client, __MODULE__.HttpClient)
  end

  @doc """
  Look up a PMID's PMC OA status + license via the client. Returns a `verification`
  map; on any transport/parse failure returns `%{found?: false, ...}` so the caller
  routes it to `:pending_review` rather than crashing a batch remediation.
  """
  @spec verify(integer() | String.t()) :: verification()
  def verify(pmid) do
    case client().lookup(to_string(pmid)) do
      {:ok, map} ->
        %{
          found?: true,
          oa?: !!map[:oa?],
          license: License.normalize(map[:license]),
          license_url: map[:license_url],
          pmcid: map[:pmcid]
        }

      {:error, reason} ->
        Logger.warning("[FullTextIntegrity] Europe PMC lookup failed for #{pmid}: #{inspect(reason)}")
        not_found()
    end
  end

  @doc "A `verification` for a PMID that could not be resolved."
  def not_found, do: %{found?: false, oa?: false, license: "unknown", license_url: nil, pmcid: nil}

  @doc """
  Reduce a `verification` to an integrity verdict (see moduledoc). Clear-cut
  non-OA-with-no-license → `:mismatch` (auto-purgeable); a CC-licensed paper not
  currently flagged OA, or an inconclusive lookup → `:pending_review`.
  """
  @spec classify(verification()) :: :verified | :mismatch | :pending_review
  def classify(%{found?: false}), do: :pending_review
  def classify(%{oa?: true}), do: :verified
  # Not in the OA subset, but carries a real CC license → ambiguous, human decides.
  def classify(%{oa?: false, license: license}) when license != "unknown", do: :pending_review
  def classify(%{oa?: false}), do: :mismatch

  @doc """
  The two columns a `StudyFullText` row should carry for a `verification`:
  `{integrity_status, full_text_displayable}`. Full text is displayable only when the
  body is `:verified` **and** the license permits commercial verbatim reuse.
  """
  @spec decision(verification()) :: %{integrity_status: String.t(), full_text_displayable: boolean()}
  def decision(verification) do
    status = classify(verification)

    %{
      integrity_status: Atom.to_string(status),
      full_text_displayable: status == :verified and License.reusable?(verification.license)
    }
  end

  defmodule HttpClient do
    @moduledoc """
    Europe PMC REST client: resolves a PMID to its `license`, `isOpenAccess`, and
    `pmcid` via the `core` result type. One call per PMID.
    """
    @behaviour Mehungry.Literature.FullTextIntegrity.ClientBehaviour

    @base "https://www.ebi.ac.uk/europepmc/webservices/rest/search"

    @impl true
    def lookup(pmid) do
      query = URI.encode_query(%{
        "query" => "EXT_ID:#{pmid} AND SRC:MED",
        "resultType" => "core",
        "format" => "json",
        "pageSize" => "1"
      })

      url = "#{@base}?#{query}"

      case HTTPoison.get(url, [{"User-Agent", "mehungry-research/1.0"}], recv_timeout: 20_000) do
        {:ok, %{status_code: 200, body: body}} -> parse(body)
        {:ok, %{status_code: code}} -> {:error, {:http, code}}
        {:error, reason} -> {:error, reason}
      end
    end

    defp parse(body) do
      with {:ok, json} <- Jason.decode(body),
           [result | _] <- get_in(json, ["resultList", "result"]) || [] do
        {:ok,
         %{
           oa?: result["isOpenAccess"] == "Y" || result["inEPMCOA"] == "Y",
           license: result["license"],
           license_url: nil,
           pmcid: result["pmcid"]
         }}
      else
        [] -> {:ok, %{oa?: false, license: nil, license_url: nil, pmcid: nil}}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
