defmodule Mehungry.Literature.PubTatorTest do
  # async: false — uses the shared global `:pubtator_cache` / `:pubchem_cache`,
  # cleared per test; serial runs keep the HTTP call-count assertions deterministic.
  use Mehungry.DataCase, async: false

  alias Mehungry.{Food, Literature, Repo}
  alias Mehungry.Food.IngredientCompoundRelationship
  alias Mehungry.Literature.{StudyEntityMention}
  alias Mehungry.Literature.PubTator.RawResponse

  # PubTator export routed by URL; the resolver's PubChem calls are stubbed
  # separately. A shared counter tracks PubTator calls so the ledger short-circuit
  # is observable.
  setup do
    {:ok, pubtator_calls} = Agent.start_link(fn -> 0 end)

    Application.put_env(:mehungry, :pubtator_http_adapter, fn _url, _h, _o ->
      Agent.update(pubtator_calls, &(&1 + 1))
      {:ok, %{status_code: 200, body: biocjson(), headers: []}}
    end)

    Application.put_env(:mehungry, :pubchem_http_adapter, fn url, _h, _o ->
      {:ok, %{status_code: 200, body: Jason.encode!(pubchem_body(url)), headers: []}}
    end)

    Cachex.clear(:pubtator_cache)
    Cachex.clear(:pubchem_cache)

    on_exit(fn ->
      Application.delete_env(:mehungry, :pubtator_http_adapter)
      Application.delete_env(:mehungry, :pubchem_http_adapter)
    end)

    %{pubtator_calls: fn -> Agent.get(pubtator_calls, & &1) end}
  end

  defp biocjson do
    Jason.encode!(%{
      "documents" => [
        %{
          "id" => "11111",
          "passages" => [
            %{
              "offset" => 0,
              "text" => "Oxalate in Spinacia oleracea and kidney stones. Oxalate again.",
              "annotations" => [
                %{
                  "infons" => %{"type" => "Chemical", "identifier" => "MESH:D010070"},
                  "text" => "Oxalate",
                  "locations" => [%{"offset" => 0, "length" => 7}]
                },
                %{
                  "infons" => %{"type" => "Species", "identifier" => "3562"},
                  "text" => "Spinacia oleracea",
                  "locations" => [%{"offset" => 11, "length" => 17}]
                },
                %{
                  "infons" => %{"type" => "Disease", "identifier" => "MESH:D007669"},
                  "text" => "kidney stones",
                  "locations" => [%{"offset" => 33, "length" => 13}]
                },
                # Same chemical mentioned again at a different offset — a distinct row.
                %{
                  "infons" => %{"type" => "Chemical", "identifier" => "MESH:D010070"},
                  "text" => "Oxalate",
                  "locations" => [%{"offset" => 48, "length" => 7}]
                }
              ]
            }
          ]
        }
      ]
    })
  end

  defp pubchem_body(url) do
    cond do
      String.contains?(url, "/cids") ->
        %{"IdentifierList" => %{"CID" => [971]}}

      String.contains?(url, "/property/") ->
        %{
          "PropertyTable" => %{
            "Properties" => [
              %{"CID" => 971, "Title" => "Oxalic acid", "MolecularFormula" => "C2H2O4"}
            ]
          }
        }

      String.contains?(url, "/synonyms") ->
        %{"InformationList" => %{"Information" => [%{"CID" => 971, "Synonym" => ["oxalate"]}]}}
    end
  end

  defp study_fixture do
    {:ok, study} = Literature.upsert_study(%{pmid: 11_111, title: "Oxalate study"})
    study
  end

  test "extracts chemical/species/disease mentions and resolves the chemical to a compound" do
    study = study_fixture()

    assert {:ok, 4} = Literature.annotate_study(study.id)

    mentions = Literature.list_entity_mentions_for_study(study.id)
    by_type = Enum.group_by(mentions, & &1.entity_type)

    # Two chemical mentions of the same entity at different offsets — both captured.
    assert length(by_type["chemical"]) == 2
    chemical = hd(by_type["chemical"])
    # MeSH stays the primary normalized identifier on the mention.
    assert chemical.normalized_identifier == "mesh:D010070"
    # The original surface text is preserved.
    assert chemical.text_span == "Oxalate"
    # The chemical resolved to a canonical compound (identity link).
    assert chemical.compound_id
    compound = Food.get_compound!(chemical.compound_id)
    assert compound.name == "Oxalic acid"
    assert Food.get_compound_by_identifier("mesh", "D010070").id == compound.id
    assert Food.get_compound_by_identifier("pubchem", 971).id == compound.id

    # Species → NCBI Taxonomy, no compound link.
    [species] = by_type["species"]
    assert species.normalized_identifier == "ncbitaxon:3562"
    assert species.compound_id == nil

    # Disease → MeSH, no compound link.
    [disease] = by_type["disease"]
    assert disease.normalized_identifier == "mesh:D007669"
    assert disease.compound_id == nil
  end

  test "no dietary relationship is ever inferred" do
    study = study_fixture()
    {:ok, _} = Literature.annotate_study(study.id)

    assert Repo.aggregate(IngredientCompoundRelationship, :count) == 0
  end

  test "re-annotating is idempotent and performs no HTTP", %{pubtator_calls: calls} do
    study = study_fixture()
    {:ok, 4} = Literature.annotate_study(study.id)
    after_first = calls.()

    assert {:ok, 0} = Literature.annotate_study(study.id)
    assert calls.() == after_first, "expected the ledger to short-circuit re-annotation"
    # Still exactly the four original mention rows.
    assert Repo.aggregate(StudyEntityMention, :count) == 4
  end

  test "every raw PubTator payload is stored append-only" do
    study = study_fixture()
    {:ok, _} = Literature.annotate_study(study.id)

    assert [%RawResponse{endpoint: "biocjson", pmid: 11_111}] = Repo.all(RawResponse)
  end

  test "a study with no mentions is ledgered as no_results" do
    Application.put_env(:mehungry, :pubtator_http_adapter, fn _url, _h, _o ->
      {:ok, %{status_code: 200, body: Jason.encode!(%{"documents" => []}), headers: []}}
    end)

    study = study_fixture()
    assert {:ok, 0} = Literature.annotate_study(study.id)
    assert Literature.annotation_attempted?(study.id)
    assert Literature.list_entity_mentions_for_study(study.id) == []
  end
end
