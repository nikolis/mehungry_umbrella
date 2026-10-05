defmodule MehungryWeb.ProfessionalLive.HealthConditionsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Health, Literature, MealBlueprints}
  alias Mehungry.Health.RecommendationCandidates

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    user = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, user)
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    %{conn: conn, user: user, oxalate: oxalate}
  end

  test "configures the analyzer service connection (URL + token) through the UI", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/professional/health")

    # The section shows the current (fallback) connection.
    assert html =~ "Analyzer service"
    assert html =~ "127.0.0.1:8000"

    view
    |> form("form[phx-submit=save_extractor_settings]", %{
      "settings" => %{
        "base_url" => "https://extractor.example.com",
        "auth_token" => "tok_123"
      }
    })
    |> render_submit()

    # Persisted and now the live connection the analyzer client uses.
    assert {"https://extractor.example.com", "tok_123"} = Mehungry.Extractor.connection()

    html = render(view)
    assert html =~ "extractor.example.com"
    assert html =~ "auth token set"
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

    assert names == ["Low-FODMAP Diet", "Mediterranean Diet"]

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

  test "creates a condition, attaches a recommendation, and removes it", %{
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

    # Attach a compound recommendation.
    view
    |> form("form[phx-submit=save_recommendation]",
      recommendation: %{
        condition_id: condition.id,
        compound_id: oxalate.id,
        recommendation: "avoid",
        severity: "high",
        source: "guideline",
        reference_label: "Clinical guideline",
        reference_url: "https://example.org"
      }
    )
    |> render_submit()

    assert [rec] = Health.recommendations_for_condition(condition.id)
    assert rec.compound_id == oxalate.id
    assert rec.recommendation == "avoid"
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

  test "searches papers for a condition, then analyzes selected PMIDs into a modal", %{
    conn: conn
  } do
    {:ok, condition} = Health.create_condition(%{name: "Crohn's Disease"})
    {:ok, study} = Literature.upsert_study(%{pmid: 990_123, title: "Fiber and remission"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "Crohn's Disease fiber"
      })

    # Stub NCBI Entrez so the crawl finds nothing new; the panel still reveals the
    # already-associated study.
    Application.put_env(:mehungry, :entrez_http_adapter, fn _url, _headers, _opts ->
      {:ok, %{status_code: 200, body: Jason.encode!(%{"esearchresult" => %{"count" => "0", "idlist" => []}}), headers: []}}
    end)

    Cachex.clear(:entrez_cache)
    on_exit(fn -> Application.delete_env(:mehungry, :entrez_http_adapter) end)

    {:ok, view, html} = live(conn, ~p"/professional/health")

    # Associated papers show permanently underneath the condition, on initial load
    # — not only after a crawl completes.
    assert html =~ "990123"
    assert html =~ "Fiber and remission"

    view
    |> element("button[phx-click=search_condition_papers][phx-value-id='#{condition.id}']")
    |> render_click()

    html = render_async(view)
    assert html =~ "990123"
    assert html =~ "Fiber and remission"

    # Analyze the study via the stubbed extractor client → claims in the modal.
    view
    |> form("form[phx-submit=analyze_condition]")
    |> render_submit(%{"pmids" => ["990123"]})

    html = render_async(view)
    assert html =~ "Batch analysis"
    assert html =~ "Dietary fiber"

    # The claim view separates verbatim extractor output from our derived layer.
    assert html =~ "From extractor"
    assert html =~ "Added by m3hungry"

    # The response was persisted at the per-paper grain and the flash reports it.
    assert html =~ "Analysis saved: 1 new"
    assert html =~ "✓ analyzed"
    assert Literature.get_analysis_by_study_id(study.id)

    # Re-analyzing the same paper reconciles: no new rows, reported as unchanged.
    view
    |> form("form[phx-submit=analyze_condition]")
    |> render_submit(%{"pmids" => ["990123"]})

    assert render_async(view) =~ "1 unchanged"

    # Expand the condition's "Claims & suggestions" block; the Claims tab lists the
    # per-paper claims extracted above ("Dietary fiber … remission").
    html =
      view
      |> element("button[phx-click=toggle_condition_detail][phx-value-id='#{condition.id}']")
      |> render_click()

    assert html =~ "Dietary fiber"

    # Assigning the "Food related" state to a claim persists it on the stored analysis.
    view
    |> form("form[phx-change=set_claim_position]", %{"position" => "food_related"})
    |> render_change()

    claims = Literature.get_analysis_by_study_id(study.id).claims
    assert Enum.find(claims, &(&1["claim_id"] == "claim-990123"))["position"] ==
             "food_related"

    # The Suggestions tab formulates the food-related claim into a suggestion
    # ("Dietary fiber improves remission" → encourage).
    html =
      view
      |> element(
        "button[phx-click=switch_condition_tab][phx-value-id='#{condition.id}'][phx-value-tab=suggestions]"
      )
      |> render_click()

    assert html =~ "Dietary fiber"
    assert html =~ "encourage"
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

    html =
      view
      |> form("#reassign-#{from.id}-#{study.id}", %{"target" => "Nonexistent Condition"})
      |> render_submit()

    assert html =~ "No condition named"
    # Untouched: still linked to the origin, no exclusion written.
    assert Enum.map(Literature.list_studies_for_condition(from.id), & &1.id) == [study.id]
    refute MapSet.member?(Literature.excluded_study_ids_for_condition(from.id), study.id)
  end

  test "Claims tab orders papers by year then sample size and shows study_design", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Ordering Test"})
    {:ok, old_small} = Literature.upsert_study(%{pmid: 100_111, title: "Old small study"})
    {:ok, new_big} = Literature.upsert_study(%{pmid: 100_222, title: "New big study"})

    for s <- [old_small, new_big] do
      {:ok, _} =
        Literature.link_study_condition(%{
          study_id: s.id,
          condition_id: condition.id,
          search_term: "ordering"
        })
    end

    insert_analysis(old_small, %{
      publication_year: 2010,
      sample_size: 50,
      study_design: "cohort"
    })

    insert_analysis(new_big, %{
      publication_year: 2024,
      sample_size: 500,
      study_design: "randomized_controlled_trial"
    })

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    html =
      view
      |> element("button[phx-click=toggle_condition_detail][phx-value-id='#{condition.id}']")
      |> render_click()

    # study_design shows in each paper's header.
    assert html =~ "randomized_controlled_trial"
    assert html =~ "cohort"

    # Newest publication (and larger sample) first: "New big study" precedes "Old small study".
    {new_pos, _} = :binary.match(html, "New big study")
    {old_pos, _} = :binary.match(html, "Old small study")
    assert new_pos < old_pos
  end

  test "Claims tab hides claim-less papers and shows a claim's disease_state", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Disease State Test"})
    # The condition has an "active flare" phase, so the claim's disease state resolves
    # to it (phases are never invented — an unmatched state would be general).
    {:ok, _} =
      Health.upsert_state(%{condition_id: condition.id, name: "active flare", slug: "active_flare"})

    {:ok, with_claims} = Literature.upsert_study(%{pmid: 200_111, title: "Paper with claims"})
    {:ok, empty} = Literature.upsert_study(%{pmid: 200_222, title: "Claim-less paper"})

    for s <- [with_claims, empty] do
      {:ok, _} =
        Literature.link_study_condition(%{
          study_id: s.id,
          condition_id: condition.id,
          search_term: "ds"
        })
    end

    insert_analysis(with_claims, %{
      claims: [
        %{
          "claim_id" => "claim-ds",
          "subject_name" => "Fiber",
          "predicate" => "improves",
          "object_name" => "remission",
          "polarity" => "positive",
          "certainty" => "asserted",
          "qualifiers" => [%{"qualifier_type" => "disease_state", "value_text" => "active flare"}]
        }
      ]
    })

    insert_analysis(empty, %{claims: []})

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    html =
      view
      |> element("button[phx-click=toggle_condition_detail][phx-value-id='#{condition.id}']")
      |> render_click()

    # The paper with claims renders a claim form (hidden study id); the claim-less
    # paper is hidden from the Claims tab (no claim form for it).
    assert has_element?(view, "form[phx-change=set_claim_position] input[value='#{with_claims.id}']")
    refute has_element?(view, "form[phx-change=set_claim_position] input[value='#{empty.id}']")

    # The claim's disease_state qualifier shows before the claim.
    assert html =~ "disease state: active flare"

    # Marking it Food related and switching to Suggestions carries the disease
    # state onto the phase-scoped suggestion.
    view
    |> element("form[phx-change=set_claim_position]")
    |> render_change(%{"position" => "food_related"})

    html =
      view
      |> element(
        "button[phx-click=switch_condition_tab][phx-value-id='#{condition.id}'][phx-value-tab=suggestions]"
      )
      |> render_click()

    assert html =~ "active flare"
    assert html =~ "Fiber"
  end

  test "Suggestions tab Refresh re-evaluates suggestions from the latest curation", %{conn: conn} do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    {:ok, condition} = Health.create_condition(%{name: "Refresh Test"})
    {:ok, study} = Literature.upsert_study(%{pmid: 300_111, title: "Oxalate paper"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "refresh"
      })

    insert_analysis(study, %{
      claims: [
        %{
          "claim_id" => "claim-ox",
          "subject_name" => "Oxalate",
          "object_name" => "stones",
          "predicate" => "increases",
          "polarity" => "positive",
          "certainty" => "asserted"
        }
      ]
    })

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element("button[phx-click=toggle_condition_detail][phx-value-id='#{condition.id}']")
    |> render_click()

    # No food_related claims yet → the Suggestions tab is empty.
    html =
      view
      |> element(
        "button[phx-click=switch_condition_tab][phx-value-id='#{condition.id}'][phx-value-tab=suggestions]"
      )
      |> render_click()

    assert html =~ "No suggestions yet"

    # Curate out-of-band (so the LiveView assigns are stale), then Refresh picks it up.
    {:ok, _} = Literature.set_claim_position(study.id, "claim-ox", "food_related")

    html =
      view
      |> element("button[phx-click=refresh_suggestions][phx-value-id='#{condition.id}']")
      |> render_click()

    refute html =~ "No suggestions yet"
    # The suggestion row is now rendered: "suggests" + the backing claim's object
    # ("stones") are unique to the suggestions list on this page.
    assert html =~ "suggests"
    assert html =~ "stones"
  end

  test "a subtype surfaces its parent condition's suggestions in a labelled inherited block",
       %{conn: conn} do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    {:ok, ibd} = Health.create_condition(%{name: "Inflammatory Bowel Disease"})
    {:ok, uc} = Health.create_condition(%{name: "Ulcerative Colitis", parent_condition_id: ibd.id})

    # UC needs at least one linked paper for its detail block to render.
    {:ok, uc_study} = Literature.upsert_study(%{pmid: 400_111, title: "UC paper"})

    {:ok, _} =
      Literature.link_study_condition(%{study_id: uc_study.id, condition_id: uc.id, search_term: "uc"})

    # The IBD (parent) has a food_related claim → a general suggestion.
    {:ok, ibd_study} = Literature.upsert_study(%{pmid: 400_222, title: "IBD paper"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: ibd_study.id,
        condition_id: ibd.id,
        search_term: "ibd"
      })

    insert_analysis(ibd_study, %{
      claims: [
        %{
          "claim_id" => "c-ibd",
          "subject_name" => "Oxalate",
          "object_name" => "stones",
          "predicate" => "increases",
          "polarity" => "positive",
          "certainty" => "asserted"
        }
      ]
    })

    {:ok, _} = Literature.set_claim_position(ibd_study.id, "c-ibd", "food_related")

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element("button[phx-click=toggle_condition_detail][phx-value-id='#{uc.id}']")
    |> render_click()

    html =
      view
      |> element(
        "button[phx-click=switch_condition_tab][phx-value-id='#{uc.id}'][phx-value-tab=suggestions]"
      )
      |> render_click()

    # The inherited block is labelled with the parent name and renders its suggestion.
    assert html =~ "Inherited from"
    assert html =~ "Inflammatory Bowel Disease"
    assert html =~ "suggests"
  end

  test "verifying a Food-related suggestion publishes it, and recalling removes it", %{
    conn: conn,
    oxalate: oxalate
  } do
    {:ok, condition} = Health.create_condition(%{name: "Kidney Stones"})
    {:ok, study} = Literature.upsert_study(%{pmid: 993_111, title: "Oxalate and stones"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "Kidney Stones diet"
      })

    insert_analysis(study, %{
      claims: [
        %{
          "claim_id" => "claim-#{study.id}",
          "subject_name" => "Oxalate",
          "predicate" => "increases",
          "object_name" => "kidney stones",
          "polarity" => "positive",
          "certainty" => "asserted"
        }
      ]
    })

    # Mark the claim Food related so it forms a counted suggestion.
    {:ok, _} = Literature.set_claim_position(study.id, "claim-#{study.id}", "food_related")

    # Not yet on the public listing (no recommendations).
    refute Enum.any?(Health.list_conditions_for_presentation(), &(&1.id == condition.id))

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element("button[phx-click=toggle_condition_detail][phx-value-id='#{condition.id}']")
    |> render_click()

    html =
      view
      |> element(
        "button[phx-click=switch_condition_tab][phx-value-id='#{condition.id}'][phx-value-tab=suggestions]"
      )
      |> render_click()

    assert html =~ "Verification"
    assert html =~ "not verified"

    # Verify it as "avoid" via the per-suggestion select.
    view
    |> form("form[phx-change=set_suggestion_verification]", %{
      "recommendation" => "avoid",
      "severity" => "moderate"
    })
    |> render_change()

    # Promoted into a public, literature-sourced compound recommendation …
    assert [rec] = Health.recommendations_for_condition(condition.id)
    assert rec.compound_id == oxalate.id
    assert rec.recommendation == "avoid"
    assert rec.source == "literature"

    # … and the condition now shows on the public /conditions listing.
    assert Enum.any?(Health.list_conditions_for_presentation(), &(&1.id == condition.id))

    # Recall it by selecting "— not verified —" (empty value).
    view
    |> form("form[phx-change=set_suggestion_verification]", %{"recommendation" => ""})
    |> render_change()

    assert Health.recommendations_for_condition(condition.id) == []
    refute Enum.any?(Health.list_conditions_for_presentation(), &(&1.id == condition.id))
  end

  # Insert a stored StudyAnalysis directly (bypassing the extractor) with a single
  # minimal claim, for driving the Claims tab.
  defp insert_analysis(study, attrs) do
    base = %{
      study_id: study.id,
      status: "included",
      source_type: "open_access",
      content_hash: "hash-#{study.id}",
      claims: [
        %{
          "claim_id" => "claim-#{study.id}",
          "subject_name" => "Fiber",
          "predicate" => "improves",
          "object_name" => "remission",
          "polarity" => "positive",
          "certainty" => "asserted"
        }
      ]
    }

    {:ok, analysis} =
      %Mehungry.Literature.StudyAnalysis{}
      |> Mehungry.Literature.StudyAnalysis.changeset(Map.merge(base, attrs))
      |> Mehungry.Repo.insert()

    analysis
  end

  test "flags a non-open-access paper unusable and hides it from the selection list", %{
    conn: conn
  } do
    {:ok, condition} = Health.create_condition(%{name: "Colitis"})
    {:ok, study} = Literature.upsert_study(%{pmid: 991_000, title: "Abstract-only paper"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "Colitis diet"
      })

    # Extractor returns this paper as abstract-only (not open_access).
    Application.put_env(:mehungry, :extractor_stub,
      analyze: fn pmids, _opts ->
        {:ok,
         %{
           "run" => %{"synthesis_version" => "0.1.0"},
           "requested_pmids" => pmids,
           "included_pmids" => pmids,
           "papers" =>
             Enum.map(pmids, fn pmid ->
               %{
                 "pmid" => pmid,
                 "status" => "included",
                 "title" => "Abstract-only paper",
                 "source_type" => "abstract"
               }
             end),
           "topic" => %{"core_concepts" => []},
           "outliers" => [],
           "paper_claims" =>
             Enum.map(pmids, fn pmid ->
               %{"pmid" => pmid, "paper_title" => "Abstract-only paper", "claims_list" => []}
             end),
           "warnings" => []
         }}
      end
    )

    on_exit(fn -> Application.delete_env(:mehungry, :extractor_stub) end)

    {:ok, view, _html} = live(conn, ~p"/professional/health")

    # Selectable before analysis — its source type isn't known yet.
    assert has_element?(view, "input[name='pmids[]'][value='991000']")

    view
    |> form("form[phx-submit=analyze_condition]")
    |> render_submit(%{"pmids" => ["991000"]})

    html = render_async(view)

    # The result modal flags the paper as unusable.
    assert html =~ "unusable · not open access"

    # It's stored non-open-access and hidden from the selection list going forward.
    assert MapSet.member?(Literature.unusable_study_ids([study.id]), study.id)
    refute has_element?(view, "input[name='pmids[]'][value='991000']")
  end

  test "non-admin is redirected away" do
    conn = log_in_user(build_conn(), user_fixture(%{email: "notadmin@example.com"}))
    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/health")
  end
end
