defmodule Mehungry.Literature.FetchStudyTest do
  use Mehungry.DataCase, async: false

  alias Mehungry.Literature

  # Same seam the Entrez client tests use: canned HTTP responses via the
  # :entrez_http_adapter app-env function.
  defp stub_xml(body) do
    Application.put_env(:mehungry, :entrez_http_adapter, fn _url, _headers, _opts ->
      {:ok, %{status_code: 200, body: body, headers: []}}
    end)

    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)
  end

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
                <PubDate><Year>2019</Year></PubDate>
              </JournalIssue>
            </Journal>
            <ArticleTitle>Oxalate content of Spinacia oleracea</ArticleTitle>
            <Abstract><AbstractText>Spinach contains high oxalate levels.</AbstractText></Abstract>
            <AuthorList>
              <Author><LastName>Smith</LastName><ForeName>Jane</ForeName></Author>
            </AuthorList>
          </Article>
        </MedlineCitation>
        <PubmedData><ArticleIdList></ArticleIdList></PubmedData>
      </PubmedArticle>
    </PubmedArticleSet>
    """
  end

  test "fetches a paper by PMID and upserts it" do
    stub_xml(sample_xml())

    assert {:ok, study} = Literature.fetch_and_upsert_study(11111)
    assert study.pmid == 11111
    assert study.title == "Oxalate content of Spinacia oleracea"
    assert study.journal == "Journal of Food Science"
  end

  test "accepts a string PMID" do
    stub_xml(sample_xml())
    assert {:ok, study} = Literature.fetch_and_upsert_study("11111")
    assert study.pmid == 11111
  end

  test "returns the stored study without hitting the network" do
    {:ok, existing} = Literature.upsert_study(%{pmid: 22222, title: "Cached"})

    Application.put_env(:mehungry, :entrez_http_adapter, fn _u, _h, _o ->
      flunk("should not hit HTTP for an already-stored PMID")
    end)

    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)

    assert {:ok, study} = Literature.fetch_and_upsert_study(22222)
    assert study.id == existing.id
  end

  test "rejects a non-numeric PMID string" do
    assert {:error, :invalid_pmid} = Literature.fetch_and_upsert_study("not-a-pmid")
  end
end
