defmodule Mehungry.Extractor.ClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.Extractor.Client` (wired up via the
  `:extractor_client` config key in `config/test.exs`) so tests never hit the
  extractor service over the network.

  Tests can override the response through app config:

      Application.put_env(:mehungry, :extractor_stub,
        analyze: fn pmids, _opts -> {:ok, %{"included_pmids" => pmids}} end
      )
      on_exit(fn -> Application.delete_env(:mehungry, :extractor_stub) end)
  """

  @behaviour Mehungry.Extractor.ClientBehaviour

  @impl true
  def analyze(pmids, opts) do
    call(:analyze, [pmids, opts], {:ok, default_response(pmids)})
  end

  defp default_response(pmids) do
    %{
      "run" => %{"synthesis_version" => "0.1.0"},
      "requested_pmids" => pmids,
      "included_pmids" => pmids,
      "papers" =>
        Enum.map(pmids, fn pmid ->
          %{
            "pmid" => pmid,
            "status" => "included",
            "title" => "Stub paper #{pmid}",
            "source_type" => "open_access"
          }
        end),
      "topic" => %{"core_concepts" => []},
      "outliers" => [],
      "paper_claims" =>
        Enum.map(pmids, fn pmid ->
          %{
            "pmid" => pmid,
            "document_id" => "doc-#{pmid}",
            "paper_title" => "Stub paper #{pmid}",
            "paper_url" => "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/",
            "claims_list" => [
              %{
                "claim_id" => "claim-#{pmid}",
                "parent_claim_id" => nil,
                "subject_concept_id" => "C-fiber",
                "subject_name" => "Dietary fiber",
                "subject_label" => "Dietary fiber",
                "subject_modifiers" => [],
                "object_concept_id" => "C-remission",
                "object_name" => "Remission",
                "object_label" => "Remission",
                "object_modifiers" => [],
                "predicate" => "improves",
                "polarity" => "positive",
                "certainty" => "asserted",
                "context" => nil,
                "qualifiers" => [],
                "evidence" => [
                  %{"quoted_text" => "Fiber intake was associated with remission."}
                ]
              }
            ]
          }
        end),
      "warnings" => []
    }
  end

  defp call(fun_name, args, default) do
    case Application.get_env(:mehungry, :extractor_stub, [])[fun_name] do
      nil -> default
      fun -> apply(fun, args)
    end
  end
end
