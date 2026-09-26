defmodule MehungryWeb.ConditionDetailSeoTest do
  # Verifies the *disconnected* HTTP render (what a crawler sees) for the
  # condition-detail page: canonical, JSON-LD @graph, and synchronous content.
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Health

  test "dead-render head contains canonical, breadcrumb + medical JSON-LD", %{conn: conn} do
    {:ok, condition} =
      Health.create_condition(%{name: "Kidney Stones", description: "Mineral deposits."})

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    # --- Canonical (base condition URL, locale-prefixed) ---
    assert html =~
             ~s(<link rel="canonical" href="https://www.m3hungry.com/en/conditions/#{condition.id}")

    # --- title / description meta (SEO-optimized, keyword-led wording) ---
    assert html =~ "Kidney Stones Diet: Foods to Eat &amp; Avoid | M3Hungry"

    # --- JSON-LD parses as valid JSON with the expected @graph nodes ---
    graph = extract_jsonld_graph(html)
    types = Enum.map(graph, & &1["@type"])
    assert "BreadcrumbList" in types
    assert "MedicalWebPage" in types

    breadcrumb = Enum.find(graph, &(&1["@type"] == "BreadcrumbList"))
    names = Enum.map(breadcrumb["itemListElement"], & &1["name"])
    assert names == ["Conditions", "Kidney Stones"]

    medical = Enum.find(graph, &(&1["@type"] == "MedicalWebPage"))
    assert medical["about"]["@type"] == "MedicalCondition"
    assert medical["about"]["name"] == "Kidney Stones"
    assert medical["url"] == "https://www.m3hungry.com/en/conditions/#{condition.id}"

    # --- #1: main content is rendered synchronously (not skeletons) ---
    assert html =~ "Kidney Stones diet suggestions"
    assert html =~ "Foods to Avoid or Limit"
  end

  test "recommendation cards link back to the PubMed source paper + carry a disclaimer", %{
    conn: conn
  } do
    {:ok, condition} = Health.create_condition(%{name: "Kidney Stones"})
    {:ok, compound} = Mehungry.Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, study} =
      Mehungry.Literature.upsert_study(%{pmid: 424_242, title: "Oxalate and stone formation"})

    {:ok, rec} =
      Health.add_recommendation(condition.id, compound.id, %{
        recommendation: "avoid",
        severity: "high",
        source: "literature"
      })

    {:ok, _} =
      %Mehungry.Health.CompoundRecommendationStudy{}
      |> Mehungry.Health.CompoundRecommendationStudy.changeset(%{
        recommendation_id: rec.id,
        study_id: study.id
      })
      |> Mehungry.Repo.insert()

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    assert html =~ "https://pubmed.ncbi.nlm.nih.gov/424242/"
    assert html =~ "Oxalate and stone formation"
    assert html =~ "not medical advice"
  end

  test "guideline recommendations render their structured source reference", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Gout"})
    {:ok, compound} = Mehungry.Food.upsert_compound(%{name: "Purine", compound_type: "purine"})

    {:ok, _} =
      Health.add_recommendation(condition.id, compound.id, %{
        recommendation: "limit",
        source: "guideline",
        source_reference: %{
          "label" => "ACR gout guideline",
          "url" => "https://rheumatology.org/gout"
        }
      })

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    assert html =~ "https://rheumatology.org/gout"
    assert html =~ "ACR gout guideline"
  end

  # Pull the @graph array out of the structured-data <script> tag. (Floki.text/1
  # drops <script> content, so read the node's raw child string directly.)
  defp extract_jsonld_graph(html) do
    json =
      html
      |> Floki.parse_document!()
      |> Floki.find(~s(script[type="application/ld+json"]))
      |> Enum.flat_map(fn {"script", _attrs, children} -> children end)
      |> Enum.find(&String.contains?(&1, "@graph"))

    {:ok, decoded} = Jason.decode(json)
    decoded["@graph"]
  end

  test "show_food deep link canonicalizes back to the base condition page", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Gout"})

    # A species id that doesn't exist would 500 on get!; use a real one.
    {:ok, species} =
      Mehungry.Food.create_foundemental_species(%{
        name: "Cherry",
        scientific_name: "Prunus avium"
      })

    html = conn |> get("/en/conditions/#{condition.id}/food/#{species.id}") |> html_response(200)

    assert html =~
             ~s(<link rel="canonical" href="https://www.m3hungry.com/en/conditions/#{condition.id}")

    refute html =~ ~s(/food/#{species.id}")
  end
end
