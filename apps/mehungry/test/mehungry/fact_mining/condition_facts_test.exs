defmodule Mehungry.FactMining.ConditionFactsTest do
  @moduledoc """
  Covers the condition branch of `Mehungry.FactMining`: mining a condition from the
  biomed-fact-miner, the `commercial_ok`-only quote gate, and the presentable-vs-
  free-claim split the nutritionist surface reads.
  """
  # async: false — mutates the `:fact_miner_stub_sheet` app env.
  use Mehungry.DataCase, async: false

  alias Mehungry.FactMining
  alias Mehungry.FactMining.ConditionFactMiningRuns, as: FactRuns
  alias Mehungry.Health
  alias Mehungry.Literature

  setup do
    {:ok, condition} = Health.create_condition(%{name: "Ulcerative Colitis"})

    # Pre-seed the publications so enrichment is a cached no-op lookup (never an
    # Entrez network call in the test).
    {:ok, _} =
      Literature.upsert_study(%{
        pmid: 111,
        title: "Dietary fiber and ulcerative colitis",
        journal: "Gut",
        citation_status: "MEDLINE"
      })

    {:ok, _} =
      Literature.upsert_study(%{pmid: 222, title: "Curcumin in UC", journal: "J Clin Gastro"})

    on_exit(fn ->
      Application.delete_env(:mehungry, :fact_miner_stub_sheet)
      Application.delete_env(:mehungry, :fact_miner_stub_last_query)
    end)

    %{condition: condition}
  end

  defp put_sheet(sheet), do: Application.put_env(:mehungry, :fact_miner_stub_sheet, sheet)

  # One commercial_ok fact (pmid 111) + one non_commercial fact (pmid 222).
  defp two_fact_sheet do
    %{
      "query" => "give me all the food related facts about Ulcerative Colitis",
      "scope_kind" => "relational",
      "counts" => %{"verified" => 1},
      "facts" => [
        %{
          "fact" => %{
            "fact_id" => "fx_1",
            "text" => "Dietary fiber is associated with reduced flares in ulcerative colitis.",
            "claim_type" => "epi_association",
            "evidence_id" => "fx_1",
            "pmid" => "111",
            "quote" => "fiber reduced disease activity",
            "char_span" => [0, 30],
            "study_design" => "systematic_review",
            "source" => "pmc_oa_fulltext",
            "pmcid" => "PMC111",
            "doi" => "10.1/fiber",
            "license" => "commercial_ok",
            "license_raw" => "CC BY"
          },
          "label" => "verified",
          "certainty" => "high",
          "reason" => "",
          "conflicting_pmid" => nil
        },
        %{
          "fact" => %{
            "fact_id" => "fx_2",
            "text" => "Curcumin may support remission in ulcerative colitis.",
            "claim_type" => "treatment_outcome",
            "evidence_id" => "fx_2",
            "pmid" => "222",
            "quote" => "curcumin improved remission rates",
            "char_span" => [5, 40],
            "study_design" => "rct",
            "source" => "pubmed_abstract",
            "pmcid" => nil,
            "doi" => "10.2/curcumin",
            "license" => "non_commercial",
            "license_raw" => "CC BY-NC"
          },
          "label" => "verified",
          "certainty" => "moderate",
          "reason" => "",
          "conflicting_pmid" => nil
        }
      ],
      "trace" => ["scope: relational"]
    }
  end

  test "mine_condition stores facts and keeps the quote only for commercial_ok", %{
    condition: condition
  } do
    put_sheet(two_fact_sheet())

    assert {:ok, counts} = FactMining.mine_condition(condition)
    assert counts.total == 2
    assert counts.verified == 2

    by_id = FactMining.list_facts_for_condition(condition.id) |> Map.new(&{&1.fact_id, &1})

    assert by_id["fx_1"].quote == "fiber reduced disease activity"
    # The API redacts the non-commercial quote under ?view=public; we never persist it.
    assert by_id["fx_2"].quote == nil
    assert by_id["fx_2"].text == "Curcumin may support remission in ulcerative colitis."
  end

  test "mining a condition replaces its previous facts (idempotent re-run)", %{
    condition: condition
  } do
    put_sheet(two_fact_sheet())
    {:ok, _} = FactMining.mine_condition(condition)
    {:ok, _} = FactMining.mine_condition(condition)

    assert FactMining.count_facts_for_condition(condition.id) == 2
  end

  test "research_for_condition splits presentable publications from free claims", %{
    condition: condition
  } do
    put_sheet(two_fact_sheet())
    {:ok, _} = FactMining.mine_condition(condition)

    research = FactMining.research_for_condition(condition.id)
    assert research.publication_count == 2
    assert research.fact_count == 2

    presentable = Enum.flat_map(research.groups, & &1.publications)
    assert [pub] = presentable
    assert pub.presentable?
    assert pub.title == "Dietary fiber and ulcerative colitis"
    assert pub.medline?
    assert [fact] = pub.facts
    assert fact.quote == "fiber reduced disease activity"

    assert [free] = research.free_publications
    refute free.presentable?
    assert free.title == "Curcumin in UC"
    assert [free_fact] = free.facts
    # The free claim carries our distilled wording but no reproduced quote.
    assert free_fact.text == "Curcumin may support remission in ulcerative colitis."
    assert free_fact.quote == nil
  end

  test "conditions_for_search counts distinct mined publications", %{condition: condition} do
    put_sheet(two_fact_sheet())
    {:ok, _} = FactMining.mine_condition(condition)

    entry = Enum.find(FactMining.conditions_for_search(), &(&1.condition.id == condition.id))
    assert entry.study_count == 2
  end

  describe "search_conditions/1 (tolerant condition search)" do
    setup %{condition: condition} do
      {:ok, ibs} =
        Health.create_condition(%{
          name: "Irritable Bowel Syndrome",
          synonyms: ["IBS"]
        })

      %{uc: condition, ibs: ibs}
    end

    defp names(entries), do: Enum.map(entries, & &1.condition.name)

    test "blank query returns the full catalog, uncorrected" do
      assert %{entries: entries, corrected: nil} = FactMining.search_conditions("")
      # Every condition appears (both the seeded UC and IBS, plus any others).
      assert "Ulcerative Colitis" in names(entries)
      assert "Irritable Bowel Syndrome" in names(entries)
    end

    test "exact name match", %{uc: uc} do
      assert %{entries: entries, corrected: nil} = FactMining.search_conditions("Ulcerative Colitis")
      assert uc.id in Enum.map(entries, & &1.condition.id)
    end

    test "word order is irrelevant (per-token AND)", %{uc: uc} do
      assert %{entries: entries, corrected: nil} = FactMining.search_conditions("colitis ulcerative")
      assert uc.id in Enum.map(entries, & &1.condition.id)
    end

    test "matches a synonym, not just the canonical name", %{ibs: ibs} do
      assert %{entries: entries} = FactMining.search_conditions("IBS")
      assert ibs.id in Enum.map(entries, & &1.condition.id)
    end

    test "accent-insensitive" do
      {:ok, cond} = Health.create_condition(%{name: "Ménière Disease"})
      assert %{entries: entries} = FactMining.search_conditions("meniere")
      assert cond.id in Enum.map(entries, & &1.condition.id)
    end

    test "typo auto-corrects and reports what it searched", %{uc: uc} do
      assert %{entries: entries, corrected: {original, suggestion}} =
               FactMining.search_conditions("ulclerative colitis")

      assert original == "ulclerative colitis"
      assert suggestion =~ "ulcerative"
      assert uc.id in Enum.map(entries, & &1.condition.id)
    end

    test "a non-condition term returns nothing, uncorrected" do
      assert %{entries: [], corrected: nil} = FactMining.search_conditions("curcumin")
    end
  end

  test "mine_condition surfaces a miner error so Oban can retry", %{condition: condition} do
    put_sheet({:error, {:network, :econnrefused}})
    assert {:error, {:network, :econnrefused}} = FactMining.mine_condition(condition)
  end

  test "mine_condition sends opts[:query] verbatim, else the default", %{condition: condition} do
    put_sheet(two_fact_sheet())

    assert {:ok, _} = FactMining.mine_condition(condition, query: "only fiber facts")
    assert Mehungry.FactMining.ClientStub.last_query() == "only fiber facts"

    assert {:ok, _} = FactMining.mine_condition(condition, query: "  ")
    assert Mehungry.FactMining.ClientStub.last_query() == FactMining.query_for_condition(condition)

    assert {:ok, _} = FactMining.mine_condition(condition)
    assert Mehungry.FactMining.ClientStub.last_query() == FactMining.query_for_condition(condition)
  end

  test "FactRuns.mine_condition/2 opens a one-row batch carrying the query", %{
    condition: condition
  } do
    assert {:ok, batch_id} = FactRuns.mine_condition(condition.id, "only fiber facts")

    assert [%{condition_id: cid, status: "pending", query: "only fiber facts"}] =
             FactRuns.list_batch_rows(batch_id)

    assert cid == condition.id
  end

  describe "FactRuns.mine_condition/2 one-in-flight defense" do
    test "refuses a second mine while one is already queued, leaving one row", %{
      condition: condition
    } do
      assert {:ok, _batch} = FactRuns.mine_condition(condition.id, "first")
      assert {:error, {:already_running, cid}} = FactRuns.mine_condition(condition.id, "second")
      assert cid == condition.id

      assert Mehungry.Repo.aggregate(Mehungry.FactMining.ConditionFactMiningRun, :count, :id) == 1
    end

    test "active_mine_for_condition/1 reflects the live job", %{condition: condition} do
      refute FactRuns.active_mine_for_condition(condition.id)
      assert {:ok, _batch} = FactRuns.mine_condition(condition.id, "q")
      assert %Oban.Job{} = FactRuns.active_mine_for_condition(condition.id)
    end

    test "allows re-mining once the prior job reaches a terminal state", %{condition: condition} do
      assert {:ok, batch1} = FactRuns.mine_condition(condition.id, "first")

      Mehungry.Repo.update_all(Oban.Job, set: [state: "completed"])
      refute FactRuns.active_mine_for_condition(condition.id)

      assert {:ok, batch2} = FactRuns.mine_condition(condition.id, "re-mine")
      assert batch2 != batch1
    end
  end
end
