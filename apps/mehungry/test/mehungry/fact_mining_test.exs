defmodule Mehungry.FactMiningTest do
  use Mehungry.DataCase, async: false

  alias Mehungry.Food
  alias Mehungry.FactMining
  alias Mehungry.FactMining.{ConditionMinedFact, SpeciesMinedFact}
  alias Mehungry.{Health, Literature}

  setup do
    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Acerola",
        "scientific_name" => "Malpighia emarginata"
      })

    on_exit(fn ->
      Application.delete_env(:mehungry, :fact_miner_stub_sheet)
      Application.delete_env(:mehungry, :fact_miner_stub_reachable)
      Application.delete_env(:mehungry, :fact_miner_stub_last_query)
    end)

    %{species: species}
  end

  defp condition_fact(condition, pmid, attrs) do
    %ConditionMinedFact{}
    |> ConditionMinedFact.changeset(
      Map.merge(
        %{
          condition_id: condition.id,
          pmid: to_string(pmid),
          label: "verified",
          certainty: "high",
          scope_kind: "relational"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp sheet(facts) do
    %{
      "query" => "q",
      "scope_kind" => "entity",
      "counts" => %{},
      "facts" => facts,
      "trace" => []
    }
  end

  defp verdict(opts) do
    %{
      "label" => opts[:label] || "verified",
      "certainty" => "high",
      "reason" => "",
      "assessment" => nil,
      "conflicting_pmid" => opts[:conflicting_pmid],
      "lay" => opts[:lay],
      "fact" => %{
        "fact_id" => opts[:fact_id] || "fx_0001",
        "text" => opts[:text] || "A biomedical fact.",
        "claim_type" => "other",
        "evidence_id" => opts[:fact_id] || "fx_0001",
        "pmid" => opts[:pmid] || "111",
        "quote" => opts[:quote] || "verbatim quote",
        "char_span" => [0, 5],
        "study_design" => opts[:study_design] || "systematic_review",
        "source" => "pmc_oa_fulltext",
        "pmcid" => "PMC1",
        "doi" => nil,
        "pub_status" => %{"retracted" => false},
        "structured_effect" => nil,
        "license" => opts[:license] || "commercial_ok",
        "license_raw" => "CC BY"
      }
    }
  end

  describe "query_for_species/1" do
    test "combines name + scientific_name", %{species: species} do
      assert FactMining.query_for_species(species) ==
               "tell me all the facts about Acerola (Malpighia emarginata)"
    end

    test "drops the parenthetical when there is no scientific name" do
      {:ok, species} = Food.create_foundemental_species(%{"name" => "Mystery Food"})
      assert FactMining.query_for_species(species) == "tell me all the facts about Mystery Food"
    end
  end

  # Wipe-insert a sheet of verdicts for `species` via the stubbed miner.
  defp mine(species, facts) do
    Application.put_env(:mehungry, :fact_miner_stub_sheet, sheet(facts))
    {:ok, _} = FactMining.mine_species(species)
  end

  describe "map_fact_sheet/2" do
    test "flattens every column", %{species: species} do
      [row] =
        FactMining.map_fact_sheet(
          sheet([verdict(text: "hello", pmid: "999")]),
          :foundemental_species_id,
          species.id
        )

      assert row.foundemental_species_id == species.id
      assert row.label == "verified"
      assert row.certainty == "high"
      assert row.fact_id == "fx_0001"
      assert row.text == "hello"
      assert row.pmid == "999"
      assert row.study_design == "systematic_review"
      assert row.scope_kind == "entity"
      assert row.char_span == [0, 5]
    end

    test "keeps the quote only for commercial_ok sources", %{species: species} do
      ok = verdict(fact_id: "fx_a", license: "commercial_ok", quote: "kept")
      nc = verdict(fact_id: "fx_b", license: "non_commercial", quote: "[quote withheld — …]")

      rows = FactMining.map_fact_sheet(sheet([ok, nc]), :foundemental_species_id, species.id)
      by_id = Map.new(rows, &{&1.fact_id, &1})

      assert by_id["fx_a"].quote == "kept"
      assert by_id["fx_b"].quote == nil
    end

    test "flattens the lay presentation hint", %{species: species} do
      v =
        verdict(lay: %{"tier" => "lead", "clarity" => 0.9, "flags" => ["off_subject:background"]})

      [row] = FactMining.map_fact_sheet(sheet([v]), :foundemental_species_id, species.id)

      assert row.lay_tier == "lead"
      assert row.lay_clarity == 0.9
      assert row.lay_flags == ["off_subject:background"]
    end

    test "lay fields are nil when the fact carries no lay block", %{species: species} do
      [row] =
        FactMining.map_fact_sheet(sheet([verdict([])]), :foundemental_species_id, species.id)

      assert row.lay_tier == nil
      assert row.lay_clarity == nil
      assert row.lay_flags == nil
    end

    test "skips facts missing fact_id/text/label and dedups by fact_id", %{species: species} do
      good = verdict(fact_id: "fx_1", text: "ok")
      no_text = verdict(fact_id: "fx_2", text: "")
      dup = verdict(fact_id: "fx_1", text: "dup")

      rows =
        FactMining.map_fact_sheet(
          sheet([good, no_text, dup]),
          :foundemental_species_id,
          species.id
        )

      assert Enum.map(rows, & &1.fact_id) == ["fx_1"]
    end
  end

  describe "mine_species/1" do
    test "inserts the sheet's facts and returns counts", %{species: species} do
      Application.put_env(
        :mehungry,
        :fact_miner_stub_sheet,
        sheet([
          verdict(fact_id: "fx_1", label: "verified"),
          verdict(fact_id: "fx_2", label: "contradicted", conflicting_pmid: "222")
        ])
      )

      assert {:ok, counts} = FactMining.mine_species(species)
      assert counts.total == 2
      assert counts.verified == 1
      assert counts.contradicted == 1

      assert FactMining.count_facts_for_species(species.id) == 2
      assert FactMining.count_facts_for_species(species.id, labels: ["verified"]) == 1
    end

    test "replaces the species' prior facts (wipe-then-insert)", %{species: species} do
      Application.put_env(:mehungry, :fact_miner_stub_sheet, sheet([verdict(fact_id: "old")]))
      assert {:ok, _} = FactMining.mine_species(species)
      assert [%{fact_id: "old"}] = FactMining.list_facts_for_species(species.id)

      Application.put_env(:mehungry, :fact_miner_stub_sheet, sheet([verdict(fact_id: "new")]))
      assert {:ok, _} = FactMining.mine_species(species)

      facts = FactMining.list_facts_for_species(species.id)
      assert Enum.map(facts, & &1.fact_id) == ["new"]
      assert Repo.aggregate(SpeciesMinedFact, :count, :id) == 1
    end

    test "propagates a client error so the worker can retry", %{species: species} do
      Application.put_env(:mehungry, :fact_miner_stub_sheet, {:error, {:network, :timeout}})
      assert {:error, {:network, :timeout}} = FactMining.mine_species(species)
    end
  end

  describe "mine_species/2 custom prompt" do
    test "sends opts[:query] verbatim to the miner", %{species: species} do
      assert {:ok, _} = FactMining.mine_species(species, query: "just the vitamin C facts")
      assert Mehungry.FactMining.ClientStub.last_query() == "just the vitamin C facts"
    end

    test "falls back to the default query when :query is nil or blank", %{species: species} do
      assert {:ok, _} = FactMining.mine_species(species, query: nil)
      assert Mehungry.FactMining.ClientStub.last_query() == FactMining.query_for_species(species)

      assert {:ok, _} = FactMining.mine_species(species, query: "   ")
      assert Mehungry.FactMining.ClientStub.last_query() == FactMining.query_for_species(species)
    end

    test "defaults the query when no opts given", %{species: species} do
      assert {:ok, _} = FactMining.mine_species(species)
      assert Mehungry.FactMining.ClientStub.last_query() == FactMining.query_for_species(species)
    end
  end

  describe "species research reads (curated top + counts + search)" do
    test "top_facts_for_species returns verified on-subject facts, lead first", %{
      species: species
    } do
      mine(species, [
        verdict(
          fact_id: "lead_hi",
          label: "verified",
          lay: %{"tier" => "lead", "clarity" => 0.9}
        ),
        verdict(
          fact_id: "show_lo",
          label: "verified",
          lay: %{"tier" => "show", "clarity" => 0.2}
        ),
        verdict(fact_id: "hidden", label: "verified", lay: %{"tier" => "hide", "clarity" => 1.0}),
        verdict(
          fact_id: "contra",
          label: "contradicted",
          conflicting_pmid: "9",
          lay: %{"tier" => "lead"}
        )
      ])

      ids = FactMining.top_facts_for_species(species.id) |> Enum.map(& &1.fact_id)
      # off-subject (hide) and non-verified (contradicted) are excluded; lead before show.
      assert ids == ["lead_hi", "show_lo"]
    end

    test "top_facts_for_species honors :limit", %{species: species} do
      mine(
        species,
        for i <- 1..5 do
          verdict(fact_id: "f#{i}", label: "verified", lay: %{"tier" => "show", "clarity" => 1.0})
        end
      )

      assert length(FactMining.top_facts_for_species(species.id, limit: 3)) == 3
    end

    test "top_facts_for_species :name_term floats facts naming the food (pre-lay data)",
         %{species: species} do
      mine(species, [
        verdict(fact_id: "named", label: "verified", text: "Cranberry is rich in polyphenols"),
        verdict(fact_id: "generic", label: "verified", text: "Polyphenols are antioxidants")
      ])

      ids =
        FactMining.top_facts_for_species(species.id, name_term: "cranberr")
        |> Enum.map(& &1.fact_id)

      assert hd(ids) == "named"
    end

    test "research_counts_for_species tallies by verdict group", %{species: species} do
      mine(species, [
        verdict(fact_id: "v", label: "verified"),
        verdict(fact_id: "c", label: "contradicted", conflicting_pmid: "1"),
        verdict(fact_id: "u", label: "unverified_quality")
      ])

      assert FactMining.research_counts_for_species(species.id) ==
               %{verified: 1, contradicted: 1, unverified: 1, total: 3}
    end

    test "curated_facts_for_species splits mechanistic facts out of the diet-relevant lead",
         %{species: species} do
      mine(species, [
        verdict(fact_id: "cohort", label: "verified", study_design: "cohort"),
        verdict(fact_id: "mech", label: "verified", study_design: "mechanistic_experiment")
      ])

      curated = FactMining.curated_facts_for_species(species.id)

      assert Enum.map(curated.relevant, & &1.fact_id) == ["cohort"]
      assert Enum.map(curated.mechanistic, & &1.fact_id) == ["mech"]
      assert curated.mechanistic_count == 1
    end

    test "curated_facts_for_species ranks human evidence above a higher-clarity mechanistic fact",
         %{species: species} do
      mine(species, [
        # mechanistic has the strongest lay signal, but study design demotes it.
        verdict(
          fact_id: "mech_hi",
          label: "verified",
          study_design: "mechanistic_experiment",
          lay: %{"tier" => "lead", "clarity" => 1.0}
        ),
        verdict(
          fact_id: "cohort_lo",
          label: "verified",
          study_design: "cohort",
          lay: %{"tier" => "show", "clarity" => 0.1}
        ),
        verdict(
          fact_id: "review_lo",
          label: "verified",
          study_design: "systematic_review",
          lay: %{"tier" => "show", "clarity" => 0.1}
        )
      ])

      curated = FactMining.curated_facts_for_species(species.id)

      # Human evidence leads, strongest-design first (systematic_review before cohort);
      # the high-clarity mechanistic fact is pushed into the collapsed pile.
      assert Enum.map(curated.relevant, & &1.fact_id) == ["review_lo", "cohort_lo"]
      assert Enum.map(curated.mechanistic, & &1.fact_id) == ["mech_hi"]
    end

    test "curated_facts_for_species on an all-mechanistic species yields an empty lead",
         %{species: species} do
      mine(species, [
        verdict(fact_id: "m1", label: "verified", study_design: "mechanistic_experiment"),
        verdict(fact_id: "m2", label: "verified", study_design: "in_vitro")
      ])

      curated = FactMining.curated_facts_for_species(species.id)

      assert curated.relevant == []
      assert Enum.map(curated.mechanistic, & &1.fact_id) |> Enum.sort() == ["m1", "m2"]
      assert curated.mechanistic_count == 2
    end

    test "search_facts_for_species matches text across all labels; blank → []",
         %{species: species} do
      mine(species, [
        verdict(fact_id: "a", label: "verified", text: "Cranberry lowers UTI risk"),
        verdict(
          fact_id: "b",
          label: "contradicted",
          conflicting_pmid: "9",
          text: "Cranberry did not reduce cholesterol"
        ),
        verdict(fact_id: "c", label: "verified", text: "Unrelated vitamin note")
      ])

      assert FactMining.search_facts_for_species(species.id, "   ") == []

      hits =
        FactMining.search_facts_for_species(species.id, "cranberry")
        |> Enum.map(& &1.fact_id)
        |> Enum.sort()

      # the contradicted fact is findable too — search spans every label.
      assert hits == ["a", "b"]
    end
  end

  describe "connection/0 + update_settings/1 (UI-managed URL + JWT)" do
    test "falls back to config/default when no row is saved" do
      Application.delete_env(:mehungry, :fact_miner_base_url)
      Application.delete_env(:mehungry, :fact_miner_auth_token)

      assert {"http://127.0.0.1:8811", nil} = FactMining.connection()
    end

    test "prefers the config over the default, trimming the trailing slash" do
      Application.put_env(:mehungry, :fact_miner_base_url, "https://miner.example.com/")
      Application.put_env(:mehungry, :fact_miner_auth_token, "env-jwt")
      on_exit(fn -> Application.delete_env(:mehungry, :fact_miner_base_url) end)
      on_exit(fn -> Application.delete_env(:mehungry, :fact_miner_auth_token) end)

      assert {"https://miner.example.com", "env-jwt"} = FactMining.connection()
    end

    test "a saved Settings row wins over config and blanks become nil" do
      Application.put_env(:mehungry, :fact_miner_base_url, "https://env.example.com")
      Application.delete_env(:mehungry, :fact_miner_auth_token)
      on_exit(fn -> Application.delete_env(:mehungry, :fact_miner_base_url) end)

      {:ok, _} =
        FactMining.update_settings(%{
          "base_url" => "https://saved.example.com/",
          "auth_token" => "saved-jwt"
        })

      assert {"https://saved.example.com", "saved-jwt"} = FactMining.connection()

      # A blank token is stored as nil, so (with no env token) there is no token.
      {:ok, _} =
        FactMining.update_settings(%{
          "base_url" => "https://saved.example.com",
          "auth_token" => ""
        })

      assert {"https://saved.example.com", nil} = FactMining.connection()
    end

    test "rejects a non-http(s) base_url" do
      assert {:error, changeset} = FactMining.update_settings(%{"base_url" => "not-a-url"})
      assert %{base_url: _} = errors_on(changeset)
    end
  end

  describe "search_condition_research/2 (within-condition weighted full-text)" do
    setup do
      {:ok, condition} = Health.create_condition(%{name: "Search Test Condition"})

      # P1: the search term lives in a FINDING (weight band A), not in the title.
      {:ok, _} =
        Literature.upsert_study(%{pmid: 70_001, title: "Trial on gut remission", journal: "Gut"})

      condition_fact(condition, 70_001, %{
        fact_id: "a1",
        text: "Magnesium supplementation improved remission."
      })

      # P2: the term lives only in the ABSTRACT (band C); its finding never mentions it.
      {:ok, _} =
        Literature.upsert_study(%{
          pmid: 70_002,
          title: "A dietary survey",
          abstract: "The survey discusses magnesium intake at length.",
          journal: "J Nutr"
        })

      condition_fact(condition, 70_002, %{
        fact_id: "b1",
        text: "Surveys reported mixed dietary results."
      })

      %{condition: condition}
    end

    test "ranks a finding-match above an abstract-only match", %{condition: condition} do
      %{results: results, result_count: count} =
        FactMining.search_condition_research(condition.id, "magnesium")

      assert count == 2
      assert [first, second] = results
      # The finding-match (band A) ranks first; the abstract-only match (band C) second.
      assert first.pmid == "70001"
      assert first.matched_in_finding
      assert second.pmid == "70002"
      refute second.matched_in_finding
    end

    test "a blank query returns no results", %{condition: condition} do
      assert %{results: [], result_count: 0} =
               FactMining.search_condition_research(condition.id, "   ")
    end

    test "a term in neither findings nor abstracts returns no results", %{condition: condition} do
      assert %{results: [], result_count: 0} =
               FactMining.search_condition_research(condition.id, "zzqnope")
    end
  end

  describe "search_all_research/2 (global cross-condition, one card per PMID)" do
    setup do
      {:ok, cond_a} = Health.create_condition(%{name: "Global Cond A"})
      {:ok, cond_b} = Health.create_condition(%{name: "Global Cond B"})

      # Paper P1 — shared across BOTH conditions, each with its own label, the term
      # in the FINDING (band A) on both sides.
      {:ok, _} = Literature.upsert_study(%{pmid: 80_001, title: "Shared omega paper", journal: "Gut"})
      condition_fact(cond_a, 80_001, %{fact_id: "s_a", text: "Omega3 reduced inflammatory markers."})

      condition_fact(cond_b, 80_001, %{
        fact_id: "s_b",
        text: "Omega3 had no effect on symptoms.",
        label: "contradicted"
      })

      # Paper P2 — the term is only in the ABSTRACT (band C); its finding omits it.
      {:ok, _} =
        Literature.upsert_study(%{
          pmid: 80_002,
          title: "A mineral survey",
          abstract: "The review discusses omega3 supplementation briefly.",
          journal: "J Nutr"
        })

      condition_fact(cond_a, 80_002, %{fact_id: "o1", text: "Iron status was unrelated to outcomes."})

      # Materialize the global index (plain form — CONCURRENTLY can't run in the
      # test transaction; mirrors the recipe_search test).
      Repo.query!("REFRESH MATERIALIZED VIEW research_search")

      %{cond_a: cond_a, cond_b: cond_b}
    end

    test "dedupes to one card per PMID, keeping each condition's own label" do
      cards = FactMining.search_all_research("omega3")

      # Two distinct papers, not four fact rows.
      assert length(cards) == 2
      pmids = Enum.map(cards, & &1.pmid)
      assert "80001" in pmids
      assert "80002" in pmids

      shared = Enum.find(cards, &(&1.pmid == "80001"))
      assert shared.any_in_finding
      labels = shared.conditions |> Enum.map(& &1.label) |> Enum.sort()
      # Both conditions present, each with its OWN label (never collapsed).
      assert labels == ["contradicted", "verified"]
    end

    test "ranks a finding-match above an abstract-only match (abstract-inclusive)" do
      cards = FactMining.search_all_research("omega3")

      assert [first, second] = cards
      assert first.pmid == "80001"
      assert first.any_in_finding
      # P2 surfaced on the abstract alone — abstract-inclusive, ranked last.
      assert second.pmid == "80002"
      refute second.any_in_finding
    end

    test "a blank query returns no cards" do
      assert FactMining.search_all_research("   ") == []
    end

    test "spelling_suggestion corrects a corpus typo (surface words, not stems)" do
      # "inflammatory" is a corpus word (a finding mentions it); the typo corrects.
      assert FactMining.spelling_suggestion("inflamatory") == "inflammatory"
      # An exact corpus word needs no correction.
      assert FactMining.spelling_suggestion("omega") == nil
    end
  end
end
