defmodule MehungryWeb.Api.V1.FoodHealthTest do
  use MehungryWeb.ConnCase, async: true

  defp species_fixture(name) do
    {:ok, species} =
      Mehungry.Food.FoundementalFoods.create_species(%{
        name: name,
        scientific_name: "Testus #{name}",
        family: "Testaceae"
      })

    species
  end

  defp insert_fact(species, attrs) do
    %Mehungry.FactMining.SpeciesMinedFact{}
    |> Mehungry.FactMining.SpeciesMinedFact.changeset(
      Map.merge(%{foundemental_species_id: species.id, label: "verified"}, attrs)
    )
    |> Mehungry.Repo.insert!()
  end

  # Curate an ingredient (USDA food) onto a species.
  defp link_ingredient(species, name) do
    ingredient = Mehungry.FoodFixtures.ingredient_fixture(%{name: name})

    %Mehungry.Food.FoundementalFood{}
    |> Mehungry.Food.FoundementalFood.changeset(%{
      foundemental_species_id: species.id,
      ingredient_id: ingredient.id,
      usda_name: name
    })
    |> Mehungry.Repo.insert!()

    ingredient
  end

  describe "species" do
    test "GET /api/v1/species lists species with meta.total", %{conn: conn} do
      species_fixture("Spinach #{System.unique_integer([:positive])}")
      conn = get(conn, ~p"/api/v1/species")

      assert %{"data" => data, "meta" => %{"total" => total}} = json_response(conn, 200)
      assert is_list(data)
      assert total >= 1
    end

    test "GET /api/v1/species/:slug returns detail", %{conn: conn} do
      name = "Kaleuniq#{System.unique_integer([:positive])}"
      species_fixture(name)
      slug = String.downcase(name)

      conn = get(conn, ~p"/api/v1/species/#{slug}")
      assert %{"data" => detail} = json_response(conn, 200)
      assert detail["name"] == name
      # The species↔compound graph was dropped; mined biomedical facts surface
      # under "research" (Mehungry.FactMining), not "compounds".
      assert %{
               "counts" => %{
                 "total" => 0,
                 "verified" => 0,
                 "contradicted" => 0,
                 "unverified" => 0
               },
               "relevant" => [],
               "mechanistic" => [],
               "mechanistic_count" => 0
             } = detail["research"]

      assert detail["ingredients"] == []
      assert detail["recipes"] == []
      assert detail["recipes_count"] == 0
      refute Map.has_key?(detail, "related_conditions")
    end

    test "GET /api/v1/species/:slug returns the curated research split + true tally",
         %{conn: conn} do
      sp = species_fixture("Curateduniq#{System.unique_integer([:positive])}")

      insert_fact(sp, %{
        fact_id: "a",
        text: "A human trial finding",
        study_design: "rct",
        lay_tier: "lead",
        reason: "Replicated in two trials."
      })

      insert_fact(sp, %{
        fact_id: "b",
        text: "A bench chemistry finding",
        study_design: "mechanistic_experiment",
        lay_tier: "lead"
      })

      insert_fact(sp, %{fact_id: "c", text: "Off subject background", lay_tier: "hide"})

      insert_fact(sp, %{
        fact_id: "d",
        text: "A disputed claim",
        label: "contradicted",
        conflicting_pmid: "9"
      })

      insert_fact(sp, %{fact_id: "e", text: "A weak claim", label: "unverified_quality"})

      conn = get(conn, ~p"/api/v1/species/#{String.downcase(sp.name)}")
      assert %{"data" => %{"research" => research}} = json_response(conn, 200)

      assert research["counts"] == %{
               "total" => 5,
               "verified" => 3,
               "contradicted" => 1,
               "unverified" => 1
             }

      assert [%{"text" => "A human trial finding", "reason" => "Replicated in two trials."}] =
               research["relevant"]

      assert [%{"text" => "A bench chemistry finding", "reason" => nil}] = research["mechanistic"]
      assert research["mechanistic_count"] == 1
    end

    test "GET /api/v1/species/:slug lists ingredients (one default) and recipes using them",
         %{conn: conn} do
      sp = species_fixture("Recipeuniq#{System.unique_integer([:positive])}")
      uniq = System.unique_integer([:positive])
      raw = link_ingredient(sp, "Zfood #{uniq}, raw")
      cooked = link_ingredient(sp, "Zfood #{uniq}, cooked")

      user = Mehungry.AccountsFixtures.user_fixture()
      mu = Mehungry.FoodFixtures.measurement_unit_fixture()

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [%{ingredient_id: raw.id, measurement_unit_id: mu.id, quantity: 2}]
        })

      conn = get(conn, ~p"/api/v1/species/#{String.downcase(sp.name)}")
      assert %{"data" => detail} = json_response(conn, 200)

      # Name-sorted; exactly one is flagged default.
      assert Enum.map(detail["ingredients"], & &1["id"]) == [cooked.id, raw.id]
      assert Enum.count(detail["ingredients"], & &1["default"]) == 1

      assert detail["recipes_count"] == 1

      assert [%{"id" => id, "title" => title, "cook_time_min" => 5} = card] = detail["recipes"]
      assert id == recipe.id
      assert title == recipe.title
      assert Map.has_key?(card, "image_url")
    end

    test "GET /api/v1/species/:slug 404 for unknown", %{conn: conn} do
      assert conn |> get(~p"/api/v1/species/no-such-species-xyz") |> json_response(404)
    end

    test "GET /api/v1/species/:slug includes only promoted enrichment facts", %{conn: conn} do
      name = "Factuniq#{System.unique_integer([:positive])}"
      sp = species_fixture(name)

      Mehungry.Food.record_species_wikidata_facts(sp.id, %{
        qid: "Q1",
        origin_region: "Andes",
        descriptions: %{"en" => "a test food"}
      })

      Mehungry.Food.record_species_faostat_facts(sp.id, [
        %{country: "Peru", tonnes: 1.0, year: 2022}
      ])

      # The Wikidata fact (origin_region) lands pending and does not surface
      # until promoted; the FAOSTAT fact auto-promotes (keyed on a curated item
      # code), so top producers surface immediately.
      conn0 = get(conn, ~p"/api/v1/species/#{String.downcase(name)}")
      assert %{"data" => %{"facts" => facts0}} = json_response(conn0, 200)
      assert facts0["origin_region"] == nil
      assert facts0["top_producers"]["countries"] == ["Peru"]

      Enum.each(
        Mehungry.Food.list_pending_species_facts(),
        &Mehungry.Food.promote_species_fact(&1.id)
      )

      conn1 = get(conn, ~p"/api/v1/species/#{String.downcase(name)}")
      assert %{"data" => %{"facts" => facts}} = json_response(conn1, 200)
      assert facts["origin_region"] == "Andes"
      assert facts["description"] == "a test food"
      assert facts["top_producers"]["countries"] == ["Peru"]
      assert facts["top_producers"]["source"] =~ "FAOSTAT"
    end
  end

  describe "species research search" do
    test "GET /api/v1/species/:slug/research searches every label, blank q is empty",
         %{conn: conn} do
      sp = species_fixture("Searchuniq#{System.unique_integer([:positive])}")
      insert_fact(sp, %{fact_id: "a", text: "Histamine content varies by variety"})

      insert_fact(sp, %{
        fact_id: "b",
        text: "Histamine claim that was disputed",
        label: "contradicted",
        conflicting_pmid: "9"
      })

      insert_fact(sp, %{fact_id: "c", text: "Unrelated potassium finding"})
      slug = String.downcase(sp.name)

      conn1 = get(conn, ~p"/api/v1/species/#{slug}/research?q=HISTAMINE")
      assert %{"data" => hits, "meta" => %{"total" => 2}} = json_response(conn1, 200)
      # Verified first, then the rest.
      assert Enum.map(hits, & &1["label"]) == ["verified", "contradicted"]

      conn2 = get(conn, ~p"/api/v1/species/#{slug}/research")
      assert %{"data" => [], "meta" => %{"total" => 0}} = json_response(conn2, 200)
    end

    test "GET /api/v1/species/:slug/research 404 for an unknown species", %{conn: conn} do
      assert conn
             |> get(~p"/api/v1/species/no-such-species-xyz/research?q=a")
             |> json_response(404)
    end
  end

  describe "species name localization" do
    defp translate(species, greek_name) do
      Mehungry.Languages.ensure_language("el")

      %Mehungry.Food.FoundementalFoodSpeciesTranslation{}
      |> Mehungry.Food.FoundementalFoodSpeciesTranslation.changeset(%{
        foundemental_species_id: species.id,
        language_name: "el",
        name: greek_name
      })
      |> Mehungry.Repo.insert!()
    end

    test "list, search and detail serve the Greek name for el; slug stays English",
         %{conn: conn} do
      uniq = System.unique_integer([:positive])
      sp = species_fixture("Eggplantq#{uniq}")
      plain = species_fixture("Untranslatedq#{uniq}")
      greek = "Μελιτζάναq#{uniq}"
      translate(sp, greek)
      slug = String.downcase(sp.name)
      el = put_req_header(conn, "accept-language", "el")

      expected = %{"name" => greek, "canonical_name" => sp.name, "slug" => slug}

      # Detail.
      assert %{"data" => detail} = el |> get(~p"/api/v1/species/#{slug}") |> json_response(200)
      assert Map.take(detail, Map.keys(expected)) == expected

      # List: the translated row is Greek, an untranslated one falls back to English.
      assert %{"data" => rows} =
               el |> get(~p"/api/v1/species?page_size=100") |> json_response(200)

      by_id = Map.new(rows, &{&1["id"], &1})

      assert Map.take(by_id[sp.id], Map.keys(expected)) == expected
      assert by_id[plain.id]["name"] == plain.name

      # Search: by the Greek name (accent-insensitive) and by the English one.
      for q <- ["μελιτζαναq#{uniq}", "eggplantq#{uniq}"] do
        assert %{"data" => [hit]} =
                 el |> get(~p"/api/v1/species?#{[q: q]}") |> json_response(200)

        assert Map.take(hit, Map.keys(expected)) == expected
      end

      # English (default) is untouched.
      assert %{"data" => %{"name" => name, "canonical_name" => name}} =
               conn |> get(~p"/api/v1/species/#{slug}") |> json_response(200)

      assert name == sp.name
    end
  end

  describe "species sub-routes resolve slugs like the detail route" do
    test "nutrition 404s for an unknown species", %{conn: conn} do
      assert conn
             |> get(~p"/api/v1/species/no-such-species-xyz/nutrition")
             |> json_response(404)
    end

    test "an un-mined species searches to an empty list", %{conn: conn} do
      sp = species_fixture("Unmineduniq#{System.unique_integer([:positive])}")

      assert %{"data" => []} =
               conn
               |> get(~p"/api/v1/species/#{String.downcase(sp.name)}/research?q=iron")
               |> json_response(200)
    end

    test "legacy punctuated and clean slugs both resolve on every species route",
         %{conn: conn} do
      uniq = System.unique_integer([:positive])
      sp = species_fixture("Duck (domesticated) q#{uniq}")
      link_ingredient(sp, "Duck q#{uniq}, raw")

      for slug <- ["Duck-(domesticated)-q#{uniq}", "Duck-domesticated-q#{uniq}"],
          path <- ["", "/nutrition", "/research?q=a"] do
        assert conn |> get("/api/v1/species/#{slug}#{path}") |> json_response(200),
               "expected 200 for #{slug}#{path}"
      end
    end
  end

  describe "species nutrition" do
    test "GET /api/v1/species/:slug/nutrition serves the default or the requested ingredient",
         %{conn: conn} do
      sp = species_fixture("Nutriuniq#{System.unique_integer([:positive])}")
      uniq = System.unique_integer([:positive])
      raw = link_ingredient(sp, "Yfood #{uniq}, raw")
      cooked = link_ingredient(sp, "Yfood #{uniq}, cooked")
      slug = String.downcase(sp.name)

      conn1 = get(conn, ~p"/api/v1/species/#{slug}/nutrition")
      assert %{"data" => data} = json_response(conn1, 200)
      # No Foundation-class food here, so the default is the first by name.
      assert data["ingredient"] == %{"id" => cooked.id, "name" => cooked.name}
      assert is_list(data["top"])
      assert is_map(data["nutrients"])
      assert is_list(data["summary"])

      conn2 = get(conn, ~p"/api/v1/species/#{slug}/nutrition?ingredient_id=#{raw.id}")
      assert %{"data" => %{"ingredient" => %{"id" => id}}} = json_response(conn2, 200)
      assert id == raw.id
    end

    test "GET /api/v1/species/:slug/nutrition 404s for a foreign ingredient or none",
         %{conn: conn} do
      sp = species_fixture("Nutri404uniq#{System.unique_integer([:positive])}")
      slug = String.downcase(sp.name)
      # No ingredient curated onto the species at all.
      assert conn |> get(~p"/api/v1/species/#{slug}/nutrition") |> json_response(404)

      link_ingredient(sp, "Xfood #{System.unique_integer([:positive])}, raw")
      foreign = Mehungry.FoodFixtures.ingredient_fixture()

      assert conn
             |> get(~p"/api/v1/species/#{slug}/nutrition?ingredient_id=#{foreign.id}")
             |> json_response(404)

      assert conn
             |> get(~p"/api/v1/species/#{slug}/nutrition?ingredient_id=abc")
             |> json_response(404)
    end
  end

  describe "search" do
    test "GET /api/v1/search returns an envelope", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/search?q=nothing-matches-xyz")
      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
    end
  end
end
