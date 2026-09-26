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
          %{"pmid" => pmid, "status" => "included", "title" => "Stub paper #{pmid}"}
        end),
      "topic" => %{"core_concepts" => []},
      "outliers" => [],
      "conclusions" => [
        %{
          "subject_name" => "Dietary fiber",
          "predicate" => "improves",
          "object_name" => "Remission",
          "direction" => "supported",
          "paper_count" => length(pmids),
          "evidence" => [%{"quoted_text" => "Fiber intake was associated with remission."}]
        }
      ],
      "facts" => %{},
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
