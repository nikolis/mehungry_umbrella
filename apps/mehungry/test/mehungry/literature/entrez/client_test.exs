defmodule Mehungry.Literature.Entrez.ClientTest do
  use ExUnit.Case, async: true

  alias Mehungry.Literature.Entrez.Client

  # Queue canned HTTP results; each adapter call pops the next, so a test can
  # script "503 then 200" retry sequences.
  defp stub_responses(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    Application.put_env(:mehungry, :entrez_http_adapter, fn _url, _headers, _opts ->
      Agent.get_and_update(agent, fn [next | rest] -> {next, rest} end)
    end)

    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)
  end

  defp ok_json(body, headers \\ []),
    do: {:ok, %{status_code: 200, body: Jason.encode!(body), headers: headers}}

  defp ok_xml(body, headers \\ []),
    do: {:ok, %{status_code: 200, body: body, headers: headers}}

  defp status(code, headers \\ []),
    do: {:ok, %{status_code: code, body: "", headers: headers}}

  defp sample_xml do
    """
    <?xml version="1.0"?>
    <PubmedArticleSet>
      <PubmedArticle>
        <MedlineCitation>
          <PMID Version="1">11111</PMID>
          <Article>
            <Journal>
              <Title>Journal of Food Science</Title>
              <JournalIssue>
                <PubDate><Year>2019</Year><Month>Mar</Month><Day>15</Day></PubDate>
              </JournalIssue>
            </Journal>
            <ArticleTitle>Oxalate content of Spinacia oleracea</ArticleTitle>
            <Abstract><AbstractText>Spinach contains high oxalate levels.</AbstractText></Abstract>
            <AuthorList>
              <Author><LastName>Smith</LastName><ForeName>Jane</ForeName></Author>
              <Author><LastName>Doe</LastName><ForeName>John</ForeName></Author>
            </AuthorList>
          </Article>
        </MedlineCitation>
        <PubmedData>
          <ArticleIdList>
            <ArticleId IdType="pubmed">11111</ArticleId>
            <ArticleId IdType="doi">10.1000/oxalate.2019</ArticleId>
          </ArticleIdList>
        </PubmedData>
      </PubmedArticle>
    </PubmedArticleSet>
    """
  end

  describe "esearch/2" do
    test "parses the PMID list and total count" do
      stub_responses([
        ok_json(%{"esearchresult" => %{"count" => "2", "idlist" => ["111", "222"]}})
      ])

      assert {:ok, [111, 222], 2, raw} = Client.esearch("Spinacia oleracea oxalate")
      assert get_in(raw, ["esearchresult", "idlist"]) == ["111", "222"]
    end

    test "an empty result set is not an error" do
      stub_responses([ok_json(%{"esearchresult" => %{"count" => "0", "idlist" => []}})])
      assert {:ok, [], 0, _raw} = Client.esearch("nonsense compound")
    end

    test "a 404 maps to :not_found" do
      stub_responses([status(404)])
      assert {:error, :not_found} = Client.esearch("whatever")
    end
  end

  describe "efetch/2" do
    test "an empty PMID list short-circuits with no HTTP" do
      # No stub installed: reaching HTTP would crash, proving no call is made.
      assert {:ok, [], %{"articles" => []}} = Client.efetch([])
    end

    test "parses PubMed XML into flat bibliographic maps" do
      stub_responses([ok_xml(sample_xml())])

      assert {:ok, [study], raw} = Client.efetch([11111])
      assert study.pmid == 11111
      assert study.doi == "10.1000/oxalate.2019"
      assert study.title == "Oxalate content of Spinacia oleracea"
      assert study.abstract == "Spinach contains high oxalate levels."
      assert study.journal == "Journal of Food Science"
      assert study.publication_date == "2019 Mar 15"
      assert study.authors == ["Jane Smith", "John Doe"]
      # The raw payload retains the original XML for the append-only cache.
      assert raw["raw_xml"] =~ "PubmedArticleSet"
    end
  end

  describe "retry / throttle" do
    test "a 503 with a short Retry-After is absorbed in-process and then succeeds" do
      stub_responses([
        status(503, [{"Retry-After", "0"}]),
        ok_json(%{"esearchresult" => %{"count" => "1", "idlist" => ["111"]}})
      ])

      assert {:ok, [111], 1, _raw} = Client.esearch("oxalate")
    end

    test "a 429 with a long Retry-After is surfaced for the caller to back off" do
      stub_responses([status(429, [{"Retry-After", "300"}])])
      assert {:error, {:rate_limited, 300}} = Client.esearch("oxalate")
    end

    test "persistent 503s surface as rate_limited after exhausting inline retries" do
      stub_responses([
        status(503, [{"Retry-After", "0"}]),
        status(503, [{"Retry-After", "0"}]),
        status(503, [{"Retry-After", "0"}])
      ])

      assert {:error, {:rate_limited, _}} = Client.esearch("oxalate")
    end

    test "a network error is retried and can recover" do
      stub_responses([
        {:error, %HTTPoison.Error{reason: :timeout}},
        ok_json(%{"esearchresult" => %{"count" => "1", "idlist" => ["111"]}})
      ])

      assert {:ok, [111], 1, _raw} = Client.esearch("oxalate")
    end
  end
end
