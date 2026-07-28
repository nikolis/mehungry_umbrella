defmodule Mehungry.Literature.EntrezTest do
  # async: false — the crawler uses the shared global `:entrez_cache`, which we
  # clear per test; serial runs keep the HTTP call-count assertions deterministic.
  use Mehungry.DataCase, async: false

  import Mehungry.FoodFixtures

  alias Mehungry.{Food, Literature, Repo}
  alias Mehungry.Literature.{ScientificStudy, StudyIngredient, StudyCompound}
  alias Mehungry.Literature.Entrez.RawResponse

  # A URL-routing stub for E-utilities that also counts calls, so tests can assert
  # the ledger short-circuit actually skips HTTP.
  setup do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Application.put_env(:mehungry, :entrez_http_adapter, fn url, _headers, _opts ->
      Agent.update(counter, &(&1 + 1))

      cond do
        String.contains?(url, "esearch.fcgi") ->
          {:ok, %{status_code: 200, body: Jason.encode!(esearch_body()), headers: []}}

        String.contains?(url, "efetch.fcgi") ->
          {:ok, %{status_code: 200, body: efetch_xml(), headers: []}}
      end
    end)

    Cachex.clear(:entrez_cache)

    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)

    %{calls: fn -> Agent.get(counter, & &1) end}
  end

  defp esearch_body, do: %{"esearchresult" => %{"count" => "1", "idlist" => ["11111"]}}

  defp efetch_xml do
    """
    <?xml version="1.0"?>
    <PubmedArticleSet>
      <PubmedArticle>
        <MedlineCitation>
          <PMID Version="1">11111</PMID>
          <Article>
            <Journal>
              <Title>Journal of Food Science</Title>
              <JournalIssue><PubDate><Year>2019</Year><Month>Mar</Month></PubDate></JournalIssue>
            </Journal>
            <ArticleTitle>Oxalate content of Spinacia oleracea</ArticleTitle>
            <Abstract><AbstractText>Spinach contains high oxalate levels.</AbstractText></Abstract>
            <AuthorList>
              <Author><LastName>Smith</LastName><ForeName>Jane</ForeName></Author>
            </AuthorList>
          </Article>
        </MedlineCitation>
        <PubmedData>
          <ArticleIdList>
            <ArticleId IdType="doi">10.1000/oxalate.2019</ArticleId>
          </ArticleIdList>
        </PubmedData>
      </PubmedArticle>
    </PubmedArticleSet>
    """
  end

  # Spinach ingredient + a "Spinacia oleracea" identity + a linked "Oxalate" compound.
  defp spinach_setup do
    ingredient = ingredient_fixture(%{name: "spinach"})

    {:ok, _identity, _} =
      Food.add_identity_candidate(%{
        ingredient_id: ingredient.id,
        scientific_name: "Spinacia oleracea",
        source: "usda_fdc",
        confidence: 0.9,
        status: "candidate"
      })

    {:ok, _rel} =
      Food.add_compound_to_ingredient(
        ingredient.id,
        %{name: "Oxalate", compound_type: "oxalate"},
        %{relationship_type: "contains", source: "literature", confidence: 0.9}
      )

    compound = Food.get_compound_by_name("Oxalate")
    %{ingredient: ingredient, compound: compound}
  end

  test "crawls the spinach/oxalate example: study, ingredient link, compound link" do
    %{ingredient: ingredient, compound: compound} = spinach_setup()

    assert {:ok, found} = Literature.import_ingredient(ingredient.id)
    assert found >= 1

    # The paper landed in the registry with all fields parsed.
    study = Literature.get_study_by_pmid(11111)
    assert study.title == "Oxalate content of Spinacia oleracea"
    assert study.abstract == "Spinach contains high oxalate levels."
    assert study.journal == "Journal of Food Science"
    assert study.doi == "10.1000/oxalate.2019"
    assert study.publication_date == "2019 Mar"
    assert study.authors == ["Jane Smith"]

    # Linked back to the ingredient with the exact search term as provenance.
    assert [linked_study] = Literature.list_studies_for_ingredient(ingredient.id)
    assert linked_study.id == study.id

    assert Repo.get_by(StudyIngredient,
             study_id: study.id,
             ingredient_id: ingredient.id,
             search_term: "Spinacia oleracea Oxalate"
           )

    # Linked to the compound (the term matched the registry).
    assert [compound_study] = Literature.list_studies_for_compound(compound.id)
    assert compound_study.id == study.id
  end

  test "the same PMID discovered under several terms yields a single study (dedup)" do
    %{ingredient: ingredient} = spinach_setup()

    assert {:ok, _} = Literature.import_ingredient(ingredient.id)

    # One compound term + five generic keywords all return PMID 11111 → one study,
    # but a StudyIngredient row per distinct term.
    assert Repo.aggregate(from(s in ScientificStudy, where: s.pmid == 11111), :count) == 1

    assert Repo.aggregate(
             from(l in StudyIngredient, where: l.ingredient_id == ^ingredient.id),
             :count
           ) == 6
  end

  test "a generic keyword term links the ingredient but not a compound" do
    %{ingredient: ingredient} = spinach_setup()

    assert {:ok, _} = Literature.import_ingredient(ingredient.id)

    # The generic "phytochemical" term produced an ingredient link…
    assert Repo.get_by(StudyIngredient,
             ingredient_id: ingredient.id,
             search_term: "Spinacia oleracea phytochemical"
           )

    # …but only the oxalate term produced a compound link, so exactly one exists.
    assert Repo.aggregate(StudyCompound, :count) == 1
  end

  test "re-crawling performs no HTTP (ledger short-circuit) and creates no duplicates", %{
    calls: calls
  } do
    %{ingredient: ingredient} = spinach_setup()

    assert {:ok, _} = Literature.import_ingredient(ingredient.id)
    after_first = calls.()
    studies_after_first = Repo.aggregate(ScientificStudy, :count)

    assert {:ok, _} = Literature.import_ingredient(ingredient.id)

    assert calls.() == after_first, "expected the crawl ledger to short-circuit all HTTP"
    assert Repo.aggregate(ScientificStudy, :count) == studies_after_first
  end

  test "raw esearch and efetch payloads are stored append-only" do
    %{ingredient: ingredient} = spinach_setup()

    assert {:ok, _} = Literature.import_ingredient(ingredient.id)

    endpoints = Repo.all(from(r in RawResponse, select: r.endpoint)) |> Enum.uniq()
    assert "esearch" in endpoints
    assert "efetch" in endpoints
  end

  test "an ingredient with no scientific identity is ledgered and produces no terms" do
    ingredient = ingredient_fixture(%{name: "mystery"})

    assert {:ok, 0} = Literature.import_ingredient(ingredient.id)
    assert Literature.search_terms_for_ingredient(ingredient.id) == []
    # Ledgered so the batch worker can still terminate.
    assert Literature.crawl_attempted?(ingredient.id, "(no scientific name)")
  end
end
