defmodule MehungryWeb.ProfessionalLive.HealthConditionsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Health, Literature, MealBlueprints}
  alias Mehungry.FactMining.ConditionFactMiningRuns
  alias Mehungry.MealBlueprints.DietPatterns
  alias Mehungry.Health.RecommendationCandidates

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    user = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, user)
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    %{conn: conn, user: user, oxalate: oxalate}
  end

  test "the 'Wipe extractor data' button clears all legacy extractor data", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Colitis"})
    {:ok, study} = Literature.upsert_study(%{pmid: 880_001, title: "Legacy paper"})
    {:ok, other} = Literature.upsert_study(%{pmid: 880_002, title: "Measurement paper"})

    # A stored extractor analysis + an extractor-sourced full text (both wiped), plus a
    # non-extractor full text (kept) and a research-ingestion run (wiped).
    {:ok, _analysis} =
      %Mehungry.Literature.StudyAnalysis{}
      |> Mehungry.Literature.StudyAnalysis.changeset(%{
        study_id: study.id,
        status: "included",
        content_hash: "hash-#{study.id}"
      })
      |> Mehungry.Repo.insert()

    {:ok, extractor_ft} =
      %Mehungry.Literature.StudyFullText{}
      |> Mehungry.Literature.StudyFullText.changeset(%{
        study_id: study.id,
        source: "mehungry_extractor",
        body: "extractor full text"
      })
      |> Mehungry.Repo.insert()

    {:ok, pmc_ft} =
      %Mehungry.Literature.StudyFullText{}
      |> Mehungry.Literature.StudyFullText.changeset(%{
        study_id: other.id,
        source: "pmc",
        body: "measurement-pipeline full text"
      })
      |> Mehungry.Repo.insert()

    {:ok, _settings} = Mehungry.Extractor.update_settings(%{"base_url" => "http://ex:8000"})
    _run = Mehungry.Literature.ResearchIngestionRuns.start_run(1)

    {:ok, view, html} = live(conn, ~p"/professional/health")
    assert has_element?(view, "button[phx-click='wipe_extractor_data']")
    refute html =~ "Analyzer service"

    html =
      view
      |> element("button[phx-click='wipe_extractor_data']")
      |> render_click()

    # Extractor data gone; the non-extractor full text and the condition survive.
    assert Literature.get_analysis_by_study_id(study.id) == nil
    assert Mehungry.Repo.get(Mehungry.Literature.StudyFullText, extractor_ft.id) == nil
    assert Mehungry.Repo.get(Mehungry.Literature.StudyFullText, pmc_ft.id)
    assert Mehungry.Extractor.get_settings() == nil
    assert Mehungry.Literature.ResearchIngestionRuns.latest_run() == nil
    assert Health.get_condition_by_name("Colitis")

    assert html =~ "Wiped legacy extractor data"
  end

  test "the Mine conditions button fans out a biomed-fact-miner batch", %{conn: conn} do
    {:ok, _c} = Health.create_condition(%{name: "Ulcerative Colitis"})

    {:ok, view, html} = live(conn, ~p"/professional/health")
    assert html =~ "Mine conditions"

    view |> element(~s(button[phx-click="mine_all_conditions"])) |> render_click()
    html = render_async(view)

    # A per-condition batch now exists (one tracking row per condition, queued on
    # :fact_mining — testing: :manual so the jobs aren't executed here).
    assert ConditionFactMiningRuns.latest_batch_id() != nil
    assert ConditionFactMiningRuns.counts_for_batch(ConditionFactMiningRuns.latest_batch_id()).total == 1
    assert html =~ "Mining started"
  end

  test "a dead fact-miner fails the mine pre-flight instead of starting", %{conn: conn} do
    {:ok, _c} = Health.create_condition(%{name: "Gout"})

    # The pre-flight reachability probe reports the miner is down.
    Application.put_env(:mehungry, :fact_miner_stub_reachable, {:error, {:network, :econnrefused}})
    on_exit(fn -> Application.delete_env(:mehungry, :fact_miner_stub_reachable) end)

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view |> element(~s(button[phx-click="mine_all_conditions"])) |> render_click()
    html = render_async(view)

    # Surfaced immediately, and no batch was started.
    assert html =~ "unreachable"
    assert html =~ "econnrefused"
    assert is_nil(ConditionFactMiningRuns.latest_batch_id())
  end

  test "a per-condition 'Mine facts' button mines just that condition", %{conn: conn} do
    {:ok, target} = Health.create_condition(%{name: "Diverticulitis"})
    {:ok, _other} = Health.create_condition(%{name: "Celiac Disease"})

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    html =
      view
      |> element(~s(button[phx-click="mine_condition"][phx-value-id="#{target.id}"]))
      |> render_click()

    html = html <> render_async(view)

    # A one-row batch for *only* the clicked condition (jobs queued on :fact_mining;
    # testing: :manual so nothing runs here).
    batch_id = ConditionFactMiningRuns.latest_batch_id()
    assert batch_id != nil
    assert ConditionFactMiningRuns.counts_for_batch(batch_id).total == 1
    assert [%{condition_id: cid}] = ConditionFactMiningRuns.list_batch_rows(batch_id)
    assert cid == target.id

    # The card reflects it: that button is now disabled "Mining…", the flash fired.
    assert html =~ "Mining started"

    assert has_element?(
             view,
             ~s(button[phx-click="mine_condition"][phx-value-id="#{target.id}"][disabled]),
             "Mining…"
           )
  end

  test "a per-condition mine fails pre-flight when the miner is dead", %{conn: conn} do
    {:ok, c} = Health.create_condition(%{name: "Pancreatitis"})

    Application.put_env(:mehungry, :fact_miner_stub_reachable, {:error, {:network, :econnrefused}})
    on_exit(fn -> Application.delete_env(:mehungry, :fact_miner_stub_reachable) end)

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element(~s(button[phx-click="mine_condition"][phx-value-id="#{c.id}"]))
    |> render_click()

    html = render_async(view)

    assert html =~ "unreachable"
    assert is_nil(ConditionFactMiningRuns.latest_batch_id())
  end

  test "the conditions list renders a client-side filter + compact, filterable cards", %{
    conn: conn
  } do
    {:ok, c} =
      Health.create_condition(%{
        name: "Psoriasis",
        category: "Dermatological",
        synonyms: ["psoriatic"]
      })

    {:ok, view, html} = live(conn, ~p"/professional/health")

    # Sticky client-side filter input (Alpine x-model, no server round-trip).
    assert has_element?(view, "input[type=search][aria-label='Filter conditions']")

    # Each card: stable id (morphdom keying) + a downcased data-search folding in
    # name + category + synonyms, + the Alpine expand toggle.
    assert html =~ ~s(id="condition-#{c.id}")
    assert html =~ "psoriasis dermatological psoriatic"
    assert html =~ "expanded = !expanded"
    # Compact count badge (both empty here).
    assert html =~ "0 advice · 0 papers"
  end

  test "the Add condition form can set a parent condition", %{conn: conn} do
    {:ok, ibd} = Health.create_condition(%{name: "Inflammatory Bowel Disease"})
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> form("form[phx-submit=save_condition]",
      condition: %{name: "Microscopic Colitis", parent_condition_id: ibd.id}
    )
    |> render_submit()

    child = Health.get_condition_by_name("Microscopic Colitis")
    assert child.parent_condition_id == ibd.id
  end

  test "the Add condition form leaves parent nil when none is selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> form("form[phx-submit=save_condition]",
      condition: %{name: "Lone Condition", parent_condition_id: ""}
    )
    |> render_submit()

    assert Health.get_condition_by_name("Lone Condition").parent_condition_id == nil
  end

  test "the 'Seed diet patterns' button creates diet-pattern blueprints, not conditions",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    assert has_element?(view, "button[phx-click='seed_diet_patterns']")
    render_click(view, "seed_diet_patterns")

    names =
      user.id |> MealBlueprints.list_blueprints_for_user() |> Enum.map(& &1.name) |> Enum.sort()

    assert names == Enum.sort(Enum.map(DietPatterns.all(), & &1.name))
    assert "Mediterranean Diet" in names
    assert "Ketogenic Diet" in names

    # They are blueprints only — no backing dietary_pattern condition is created.
    refute Health.get_condition_by_name("Mediterranean Diet")
    refute Health.get_condition_by_name("Low-FODMAP Diet")
  end

  test "the 'Clear all suggestions' button wipes candidates + recommendations", %{
    conn: conn,
    oxalate: oxalate
  } do
    {:ok, condition} = Health.create_condition(%{name: "Wipe Me", category: "test"})

    {:ok, _} =
      Health.add_recommendation(condition.id, oxalate.id, %{
        recommendation: "avoid",
        severity: "moderate",
        evidence_level: "moderate",
        source: "manual",
        source_reference: %{"label" => "t", "url" => "https://x"}
      })

    assert Health.recommendations_for_condition(condition.id) != []

    {:ok, view, _html} = live(conn, ~p"/professional/health")
    assert has_element?(view, "button[phx-click='clear_all_recommendations']")
    render_click(view, "clear_all_recommendations")

    assert Health.recommendations_for_condition(condition.id) == []
    # Condition itself survives.
    assert Health.get_condition_by_name("Wipe Me")
  end

  test "creates a condition, lists an attached recommendation, and removes it", %{
    conn: conn,
    oxalate: oxalate
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    # Create a condition.
    view
    |> form("form[phx-submit=save_condition]",
      condition: %{name: "Kidney Stones", category: "renal"}
    )
    |> render_submit()

    assert render(view) =~ "Kidney Stones"
    condition = Health.get_condition_by_name("Kidney Stones")
    assert condition

    # Recommendations arrive through the review-gated flows (candidate promote /
    # suggestion verify), not a direct form — attach via the context, then assert
    # it is listed with a working Remove action.
    {:ok, rec} =
      Health.add_recommendation(condition.id, oxalate.id, %{
        recommendation: "avoid",
        severity: "high",
        source: "guideline",
        source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
      })

    {:ok, view, _html} = live(conn, ~p"/professional/health")
    assert render(view) =~ "Oxalate"

    # Remove the recommendation.
    view
    |> element("button[phx-click=delete_recommendation][phx-value-id='#{rec.id}']")
    |> render_click()

    assert Health.recommendations_for_condition(condition.id) == []
  end

  test "deletes a condition and its recommendations", %{conn: conn, oxalate: oxalate} do
    {:ok, _} =
      Health.add_recommendation(%{name: "Gout", category: "metabolic"}, oxalate.id, %{
        recommendation: "limit",
        source: "guideline",
        source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
      })

    gout = Health.get_condition_by_name("Gout")
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element("button[phx-click=delete_condition][phx-value-id='#{gout.id}']")
    |> render_click()

    assert Health.get_condition(gout.id) == nil
    assert Health.recommendations_for_condition(gout.id) == []
  end

  test "reviews a literature-derived candidate and promotes it into a recommendation", %{
    conn: conn,
    oxalate: oxalate
  } do
    {:ok, condition} = Health.create_condition(%{name: "Kidney Stones"})
    {:ok, study} = Literature.upsert_study(%{pmid: 770_001, title: "s"})

    {:ok, _} =
      Literature.upsert_entity_relation(%{
        study_id: study.id,
        type: "Positive_Correlation",
        score: 0.98,
        entity1_type: "chemical",
        entity1_identifier: "mesh:D010070",
        entity2_type: "disease",
        entity2_identifier: "mesh:D007669",
        compound_id: oxalate.id,
        condition_id: condition.id
      })

    {:ok, %{candidate: candidate}} =
      RecommendationCandidates.derive_candidate(condition.id, oxalate.id)

    {:ok, view, _html} = live(conn, ~p"/professional/health")
    assert render(view) =~ "Review derived recommendations"
    assert render(view) =~ "suggests avoid"

    view
    |> form("form[phx-submit=promote_recommendation]",
      candidate_id: candidate.id,
      recommendation: "avoid",
      severity: "high"
    )
    |> render_submit()

    assert [rec] = Health.recommendations_for_condition(condition.id)
    assert rec.recommendation == "avoid"
    assert rec.source == "literature"
    assert rec.compound_id == oxalate.id
    # Promoted candidate leaves the review queue.
    assert RecommendationCandidates.list_pending_candidates() == []
  end

  test "re-assigns a discovered paper to a better-fitting condition, flagging the origin", %{
    conn: conn
  } do
    {:ok, from} = Health.create_condition(%{name: "Gout"})
    {:ok, to} = Health.create_condition(%{name: "Hyperuricemia"})
    {:ok, study} = Literature.upsert_study(%{pmid: 990_777, title: "Purine metabolism"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: from.id,
        search_term: ~s("Gout"[tiab] AND diet)
      })

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    # The re-assign form lives in the papers collapse, which is rendered on demand.
    view
    |> element("button[phx-click=toggle_condition_papers][phx-value-id='#{from.id}']")
    |> render_click()

    view
    |> form("#reassign-#{from.id}-#{study.id}", %{"target" => "Hyperuricemia"})
    |> render_submit()

    # Moved to the target, removed from the origin, origin flagged.
    assert Enum.map(Literature.list_studies_for_condition(to.id), & &1.id) == [study.id]
    assert Literature.list_studies_for_condition(from.id) == []
    assert MapSet.member?(Literature.excluded_study_ids_for_condition(from.id), study.id)
  end

  test "rejects a re-assignment to an unknown condition name", %{conn: conn} do
    {:ok, from} = Health.create_condition(%{name: "Gout"})
    {:ok, study} = Literature.upsert_study(%{pmid: 990_778, title: "Purines"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: from.id,
        search_term: "Gout diet"
      })

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element("button[phx-click=toggle_condition_papers][phx-value-id='#{from.id}']")
    |> render_click()

    html =
      view
      |> form("#reassign-#{from.id}-#{study.id}", %{"target" => "Nonexistent Condition"})
      |> render_submit()

    assert html =~ "No condition named"
    # Untouched: still linked to the origin, no exclusion written.
    assert Enum.map(Literature.list_studies_for_condition(from.id), & &1.id) == [study.id]
    refute MapSet.member?(Literature.excluded_study_ids_for_condition(from.id), study.id)
  end

  test "non-admin is redirected away" do
    conn = log_in_user(build_conn(), user_fixture(%{email: "notadmin@example.com"}))
    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/health")
  end
end
