defmodule MehungryLocalAi.PMCTest do
  use ExUnit.Case, async: false

  alias MehungryLocalAi.PMC
  alias MehungryLocalAi.PMC.Parser

  describe "Parser.to_text/1" do
    test "extracts body text and decodes entities" do
      xml = jats("L-Ascorbic Acid content was 260 mg/100 g &amp; rising.")
      text = Parser.to_text(xml)
      assert text =~ "260 mg/100 g & rising"
    end

    test "empty for non-binary" do
      assert Parser.to_text(nil) == ""
    end
  end

  describe "PMC.fetch/1 (stubbed HTTP)" do
    test "returns open_access with body when the paper is OA" do
      stub(fn url ->
        cond do
          String.contains?(url, "idconv") ->
            {:ok, %{status_code: 200, body: Jason.encode!(%{"records" => [%{"pmcid" => "PMC42"}]})}}

          String.contains?(url, "efetch") ->
            body =
              "Results. L-Ascorbic Acid content was 260 mg/100 g by HPLC. " <>
                String.duplicate("Further composition analysis is discussed here. ", 6)

            {:ok, %{status_code: 200, body: jats(body)}}
        end
      end)

      assert {:ok, %{outcome: "open_access", pmcid: "PMC42", body: body}} = PMC.fetch(12_345)
      assert body =~ "260 mg/100 g"
    end

    test "returns no_pmcid when the paper is not in PMC" do
      stub(fn _url ->
        {:ok, %{status_code: 200, body: Jason.encode!(%{"records" => [%{"status" => "error"}]})}}
      end)

      assert {:ok, %{outcome: "no_pmcid", pmcid: nil, body: nil}} = PMC.fetch(12_345)
    end
  end

  defp stub(fun) do
    Application.put_env(:mehungry_local_ai, :pmc_http_adapter, fn url, _headers, _opts -> fun.(url) end)
    on_exit(fn -> Application.delete_env(:mehungry_local_ai, :pmc_http_adapter) end)
  end

  defp jats(body_text) do
    """
    <?xml version="1.0"?>
    <article><front><article-meta><title-group><article-title>T</article-title></title-group></article-meta></front>
    <body><sec><p>#{body_text}</p></sec></body></article>
    """
  end
end
