defmodule Mehungry.Literature.ConditionCrawlTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.{Health, Literature}

  defp condition_with_state(name) do
    {:ok, c} = Health.create_condition(%{name: name})
    {:ok, _} = Health.upsert_state(%{condition_id: c.id, name: "Active Flare", slug: "active_flare", is_default: true})
    c
  end

  describe "search_terms_for_condition/1" do
    test "crosses the name with the dietary/phase keyword set" do
      {:ok, c} = Health.create_condition(%{name: "Gout"})
      terms = Literature.search_terms_for_condition(c.id)

      assert length(terms) == 9
      assert Enum.all?(terms, &(&1.condition_id == c.id))
      assert "Gout diet" in Enum.map(terms, & &1.term)
      assert "Gout flare" in Enum.map(terms, & &1.term)
    end

    test "returns [] for a missing condition" do
      assert Literature.search_terms_for_condition(-1) == []
    end
  end

  describe "ledger + batch selection" do
    test "only state-bearing, un-attempted conditions are selected; progress tracks coverage" do
      with_state = condition_with_state("Ulcerative Colitis")
      {:ok, _stateless} = Health.create_condition(%{name: "Kidney Stones"})

      ids = Literature.list_uncrawled_conditions(50) |> Enum.map(& &1.id)
      assert with_state.id in ids
      # a condition with no states is never crawled
      refute Enum.any?(Literature.list_uncrawled_conditions(50), &(&1.name == "Kidney Stones"))

      assert %{processed: 0, total: 1} = Literature.condition_crawl_progress()

      {:ok, _} =
        Literature.record_condition_crawl_attempt(%{
          condition_id: with_state.id,
          search_term: "Ulcerative Colitis diet",
          outcome: "matched",
          studies_found: 2,
          last_crawled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert Literature.condition_crawl_attempted?(with_state.id, "Ulcerative Colitis diet")
      assert %{processed: 1, total: 1} = Literature.condition_crawl_progress()
      # the pair is excluded on re-selection only if ALL its terms are attempted; one
      # attempt leaves it selectable (other terms remain), but attempted? is per-term.
      refute Literature.condition_crawl_attempted?(with_state.id, "Ulcerative Colitis fiber")
    end
  end

  describe "study ↔ condition link" do
    test "link + list_studies_for_condition, deduped, newest first" do
      c = condition_with_state("Crohn's Disease")
      {:ok, s1} = Literature.upsert_study(%{pmid: 800_001, title: "older"})
      {:ok, s2} = Literature.upsert_study(%{pmid: 800_002, title: "newer"})

      {:ok, _} = Literature.link_study_condition(%{study_id: s1.id, condition_id: c.id, search_term: "Crohn's Disease diet"})
      {:ok, _} = Literature.link_study_condition(%{study_id: s2.id, condition_id: c.id, search_term: "Crohn's Disease fiber"})
      # same (study, condition, term) is idempotent
      {:ok, _} = Literature.link_study_condition(%{study_id: s1.id, condition_id: c.id, search_term: "Crohn's Disease diet"})

      studies = Literature.list_studies_for_condition(c.id)
      assert Enum.map(studies, & &1.id) == [s2.id, s1.id]
    end
  end
end
