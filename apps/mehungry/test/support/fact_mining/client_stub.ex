defmodule Mehungry.FactMining.ClientStub do
  @moduledoc """
  Test stub for the biomed-fact-miner client (`:fact_miner_client` seam). Tests
  control its behaviour via app config keys:

    * `:fact_miner_stub_sheet` — the `FactSheet.to_dict()` map returned by `mine/2`
      (default a minimal verified sheet), **or** an `{:error, reason}` tuple to
      simulate a failed call.
    * `:fact_miner_stub_reachable` — `:ok` (default) or `{:error, reason}`.
  """

  @behaviour Mehungry.FactMining.ClientBehaviour

  @impl true
  def mine(_query, _opts \\ []) do
    case Application.get_env(:mehungry, :fact_miner_stub_sheet, default_sheet()) do
      {:error, _} = err -> err
      %{} = sheet -> {:ok, sheet}
    end
  end

  @impl true
  def reachable? do
    Application.get_env(:mehungry, :fact_miner_stub_reachable, :ok)
  end

  defp default_sheet do
    %{
      "query" => "tell me all the facts about Acerola (Malpighia emarginata)",
      "scope_kind" => "entity",
      "counts" => %{"verified" => 1},
      "facts" => [
        %{
          "fact" => %{
            "fact_id" => "fx_0001",
            "text" => "Acerola is an exceptionally rich dietary source of vitamin C.",
            "claim_type" => "other",
            "evidence_id" => "fx_0001",
            "pmid" => "12345678",
            "quote" => "acerola is extremely rich in ascorbic acid",
            "char_span" => [10, 52],
            "study_design" => "systematic_review",
            "source" => "pmc_oa_fulltext",
            "pmcid" => "PMC12345",
            "doi" => "10.1/acerola",
            "pub_status" => %{"retracted" => false, "corrected" => false, "has_erratum" => false},
            "structured_effect" => nil,
            "license" => "commercial_ok",
            "license_raw" => "CC BY"
          },
          "label" => "verified",
          "certainty" => "high",
          "reason" => "",
          "assessment" => nil,
          "conflicting_pmid" => nil
        }
      ],
      "trace" => ["scope: entity"]
    }
  end
end
