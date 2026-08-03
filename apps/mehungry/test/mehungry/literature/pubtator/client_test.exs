defmodule Mehungry.Literature.PubTator.ClientTest do
  use ExUnit.Case, async: false

  alias Mehungry.Literature.PubTator.Client

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :pubtator_http_adapter) end)
    :ok
  end

  defp stub(fun), do: Application.put_env(:mehungry, :pubtator_http_adapter, fun)

  defp ok(body), do: {:ok, %{status_code: 200, body: body, headers: []}}

  # A BioC JSON collection with one document carrying a title passage with a
  # Chemical, a Species, a Disease, and a Gene (which must be dropped).
  defp biocjson do
    Jason.encode!(%{
      "documents" => [
        %{
          "id" => "11111",
          "passages" => [
            %{
              "offset" => 0,
              "text" => "Oxalate content of Spinacia oleracea and kidney stones in Homo sapiens.",
              "annotations" => [
                %{
                  "infons" => %{
                    "type" => "Chemical",
                    "identifier" => "MESH:D010070",
                    "score" => "0.99"
                  },
                  "text" => "Oxalate",
                  "locations" => [%{"offset" => 0, "length" => 7}]
                },
                %{
                  "infons" => %{"type" => "Species", "identifier" => "3562"},
                  "text" => "Spinacia oleracea",
                  "locations" => [%{"offset" => 19, "length" => 17}]
                },
                %{
                  "infons" => %{"type" => "Disease", "identifier" => "MESH:D007669"},
                  "text" => "kidney stones",
                  "locations" => [%{"offset" => 41, "length" => 13}]
                },
                %{
                  "infons" => %{"type" => "Species", "identifier" => "NCBITaxon:9606"},
                  "text" => "Homo sapiens",
                  "locations" => [%{"offset" => 58, "length" => 12}]
                },
                %{
                  "infons" => %{"type" => "Gene", "identifier" => "12345"},
                  "text" => "AGXT",
                  "locations" => [%{"offset" => 71, "length" => 4}]
                },
                %{
                  "infons" => %{"type" => "Chemical", "identifier" => "-"},
                  "text" => "unnormalized compound",
                  "locations" => [%{"offset" => 80, "length" => 21}]
                }
              ]
            }
          ]
        }
      ]
    })
  end

  test "parses Chemical/Species/Disease mentions and drops Gene" do
    stub(fn _url, _h, _o -> ok(biocjson()) end)

    {:ok, mentions, raw} = Client.annotate([11_111])

    types = Enum.map(mentions, & &1.entity_type) |> Enum.sort()
    assert types == ["chemical", "chemical", "disease", "species", "species"]
    refute Enum.any?(mentions, &(&1.entity_type == "gene"))
    assert %{"documents" => [_]} = raw
  end

  test "normalizes identifiers per namespace" do
    stub(fn _url, _h, _o -> ok(biocjson()) end)

    {:ok, mentions, _raw} = Client.annotate([11_111])
    by_text = Map.new(mentions, &{&1.text_span, &1})

    # Chemical / Disease → MeSH (prefix lowercased).
    assert by_text["Oxalate"].normalized_identifier == "mesh:D010070"
    assert by_text["Oxalate"].confidence == 0.99
    assert by_text["Oxalate"].offset == 0
    assert by_text["kidney stones"].normalized_identifier == "mesh:D007669"
    # Species → NCBI Taxonomy, whether bare taxid or prefixed.
    assert by_text["Spinacia oleracea"].normalized_identifier == "ncbitaxon:3562"
    assert by_text["Homo sapiens"].normalized_identifier == "ncbitaxon:9606"
    # An unnormalized ("-") mention keeps its text but has no identifier.
    assert by_text["unnormalized compound"].normalized_identifier == nil
  end

  test "empty PMID list short-circuits with no HTTP" do
    stub(fn _url, _h, _o -> flunk("should not hit HTTP") end)
    assert {:ok, [], %{"documents" => []}} = Client.annotate([])
  end

  test "404 maps to :not_found" do
    stub(fn _url, _h, _o -> {:ok, %{status_code: 404, body: "", headers: []}} end)
    assert {:error, :not_found} = Client.annotate([11_111])
  end

  test "503 retries then succeeds" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    stub(fn _url, _h, _o ->
      n = Agent.get_and_update(counter, &{&1, &1 + 1})

      if n == 0,
        do: {:ok, %{status_code: 503, body: "", headers: [{"Retry-After", "1"}]}},
        else: ok(biocjson())
    end)

    assert {:ok, mentions, _raw} = Client.annotate([11_111])
    assert length(mentions) == 5
    assert Agent.get(counter, & &1) == 2
  end

  test "a long Retry-After surfaces as {:rate_limited, _}" do
    stub(fn _url, _h, _o ->
      {:ok, %{status_code: 429, body: "", headers: [{"Retry-After", "120"}]}}
    end)

    assert {:error, {:rate_limited, 120}} = Client.annotate([11_111])
  end

  describe "parse_relations/1" do
    test "parses directional relations, normalizing endpoint identifiers" do
      raw = %{
        "PubTator3" => [
          %{
            "relations" => [
              %{
                "id" => "R1",
                "infons" => %{
                  "type" => "Negative_Correlation",
                  "score" => "0.9989",
                  "role1" => %{
                    "biotype" => "chemical",
                    "identifier" => "MESH:D005419",
                    "name" => "Flavonoids"
                  },
                  "role2" => %{
                    "biotype" => "disease",
                    "identifier" => "MESH:D007249",
                    "name" => "Inflammation"
                  }
                }
              }
            ]
          }
        ]
      }

      assert [rel] = Client.parse_relations(raw)
      assert rel.type == "Negative_Correlation"
      assert rel.score == 0.9989
      assert rel.entity1_type == "chemical"
      assert rel.entity1_identifier == "mesh:D005419"
      assert rel.entity2_type == "disease"
      assert rel.entity2_identifier == "mesh:D007249"
      assert rel.entity2_name == "Inflammation"
    end

    test "returns [] for documents without a relations array" do
      assert Client.parse_relations(%{"PubTator3" => [%{"passages" => []}]}) == []
      assert Client.parse_relations(%{"documents" => []}) == []
    end
  end
end
