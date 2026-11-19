defmodule MehungryWeb.NutritionistLive.ResearchTest do
  @moduledoc """
  Smoke tests for the nutritionist research search engine: the catalog landing
  (search by condition) and the per-condition results page — publications mined by
  the external biomed-fact-miner (`Mehungry.FactMining`), split into **presentable**
  cards (with verbatim quotes) and **free claims** (distilled wording + source link
  only). The legacy full-text reader shell is covered in its own describe block.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Literature, Professionals, Subscriptions}
  alias Mehungry.FactMining.ConditionMinedFact
  alias Mehungry.Literature.StudyCondition
  alias Mehungry.Professionals.ResearchNotes
  alias Mehungry.Repo

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    {:ok, _profile} =
      Professionals.create_professional_profile(%{
        user_id: nutritionist.id,
        specialization: "Dietitian",
        display_name: "Maria Papadaki",
        city: "Rethymno",
        bio: "Clinical dietitian.",
        is_public: true
      })

    {:ok, condition} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})

    # A presentable (commercial_ok) publication and a free (non_commercial) one.
    {:ok, open} =
      Literature.upsert_study(%{
        pmid: 55_001,
        title: "Dietary fiber in ulcerative colitis",
        journal: "Gut",
        authors: ["Smith J", "Doe A", "Roe B"],
        citation_status: "MEDLINE"
      })

    {:ok, restricted} =
      Literature.upsert_study(%{pmid: 55_002, title: "Curcumin in UC", journal: "J Clin Gastro"})

    mine_fact(condition, 55_001, %{
      fact_id: "fx1",
      text: "Dietary fiber is associated with remission in ulcerative colitis.",
      quote: "fiber improved remission rates",
      license: "commercial_ok",
      study_design: "randomized_controlled_trial"
    })

    mine_fact(condition, 55_002, %{
      fact_id: "fx2",
      text: "Curcumin may support remission in ulcerative colitis.",
      quote: nil,
      license: "non_commercial",
      study_design: "cohort"
    })

    # A contradicted free claim — hidden under the default (Verified) filter.
    mine_fact(condition, 55_002, %{
      fact_id: "fx3",
      text: "Fiber worsens flares in ulcerative colitis.",
      quote: nil,
      label: "contradicted",
      license: "non_commercial",
      study_design: "cohort"
    })

    %{
      conn: log_in_user(conn, nutritionist),
      condition: condition,
      nutritionist: nutritionist,
      open_study: open,
      restricted_study: restricted
    }
  end

  defp mine_fact(condition, pmid, attrs) do
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

  test "catalog lists conditions with mined facts and filters by search", %{
    conn: conn,
    condition: condition
  } do
    {:ok, view, html} = live(conn, ~p"/nutritionist/research")

    assert html =~ "Ulcerative Colitis"
    assert html =~ "2 studies"

    link = ~s(a[href="/nutritionist/research/#{condition.id}"])
    search = fn q -> view |> element("#research-search-form") |> render_change(%{"q" => q}) end

    search.("coli")
    assert has_element?(view, link)
    search.("zzz-nope")
    refute has_element?(view, link)
  end

  test "conditions search tolerates word order and auto-corrects typos", %{
    conn: conn,
    condition: condition
  } do
    {:ok, view, _html} = live(conn, ~p"/nutritionist/research")

    link = ~s(a[href="/nutritionist/research/#{condition.id}"])
    search = fn q -> view |> element("#research-search-form") |> render_change(%{"q" => q}) end

    # Reversed word order still resolves (per-token AND over the name).
    search.("colitis ulcerative")
    assert has_element?(view, link)

    # A typo auto-corrects and the banner names what we searched.
    html = search.("ulclerative colitis")
    assert has_element?(view, link)
    assert html =~ "Showing results for"
  end

  test "a non-condition term offers to run the global search", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nutritionist/research")

    html =
      view |> element("#research-search-form") |> render_change(%{"q" => "curcumin"})

    assert html =~ "Search all research"
    # The button flips the mode to the global search without a new event type.
    assert has_element?(view, ~s(button[phx-click="set_mode"][phx-value-mode="papers"]))
  end

  test "results page shows presentable publications grouped by research type, with quotes", %{
    conn: conn,
    condition: condition
  } do
    {:ok, _view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

    # Grouped under the strongest-evidence bucket.
    assert html =~ "Randomized &amp; controlled trials"
    assert html =~ "Dietary fiber in ulcerative colitis"
    assert html =~ "Gut"
    assert html =~ "Smith J"
    assert html =~ "MEDLINE"
    # The distilled fact + its verbatim quote (we may reproduce it: commercial_ok).
    assert html =~ "Dietary fiber is associated with remission"
    assert html =~ "fiber improved remission rates"
    assert html =~ "https://pubmed.ncbi.nlm.nih.gov/55001/"
  end

  test "non-presentable publications appear as free claims without a quote", %{
    conn: conn,
    condition: condition
  } do
    {:ok, _view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

    assert html =~ "Free claims"
    assert html =~ "full text not shown"
    assert html =~ "Curcumin may support remission"
    assert html =~ "https://pubmed.ncbi.nlm.nih.gov/55002/"
    # The non-commercial quote is never persisted or shown.
    refute html =~ "curcumin improved remission"
  end

  test "offers the sort control with the fact-derived options", %{conn: conn, condition: condition} do
    {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

    assert has_element?(view, "select#sort option[value=newest]")
    assert has_element?(view, "select#sort option[value=findings]")

    assert view
           |> element("form[phx-change=set_sort]")
           |> render_change(%{"sort" => "newest"}) =~ "Dietary fiber in ulcerative colitis"
  end

  test "defaults to Verified + Unverified and reveals contradicted findings on toggle", %{
    conn: conn,
    condition: condition
  } do
    {:ok, view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

    # Default (verified + unverified selected): verified facts show, contradicted hidden.
    assert html =~ "Dietary fiber is associated with remission"
    refute html =~ "Fiber worsens flares"

    # The label chips render as independent toggles.
    assert has_element?(
             view,
             ~s(button[phx-click="toggle_label"][phx-value-label="contradicted"])
           )

    # Turning on the Contradicted chip reveals the contradicted finding, without
    # dropping the already-shown verified ones.
    revealed =
      view
      |> element(~s(button[phx-click="toggle_label"][phx-value-label="contradicted"]))
      |> render_click()

    assert revealed =~ "Fiber worsens flares"
    assert revealed =~ "Dietary fiber is associated with remission"
  end

  test "collapses each publication's findings behind a disclosure toggle", %{
    conn: conn,
    condition: condition
  } do
    {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")
    assert has_element?(view, "button", "finding")
  end

  describe "within-condition search" do
    defp search(view, q) do
      view |> element("#condition-research-search") |> render_change(%{"q" => q})
    end

    test "ranks a finding-match above a title/abstract-only match", %{
      conn: conn,
      condition: condition
    } do
      # P1 — the term is a FINDING (weight band A), absent from the title.
      {:ok, _} =
        Literature.upsert_study(%{pmid: 60_001, title: "Trial on gut remission", journal: "Gut"})

      mine_fact(condition, 60_001, %{
        fact_id: "mg1",
        text: "Magnesium supplementation improved remission.",
        license: "commercial_ok",
        study_design: "randomized_controlled_trial"
      })

      # P2 — the term lives only in the ABSTRACT (band C); its finding omits it.
      {:ok, _} =
        Literature.upsert_study(%{
          pmid: 60_002,
          title: "A dietary survey",
          abstract: "The survey discusses magnesium intake.",
          journal: "J Nutr"
        })

      mine_fact(condition, 60_002, %{
        fact_id: "mg2",
        text: "Surveys reported mixed dietary results.",
        license: "commercial_ok",
        study_design: "randomized_controlled_trial"
      })

      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")
      html = search(view, "magnesium")

      # Both papers surface; the finding-match ranks first and self-labels.
      assert html =~ "Trial on gut remission"
      assert html =~ "A dietary survey"
      assert html =~ "Matched in a finding"

      {p1, _} = :binary.match(html, "Trial on gut remission")
      {p2, _} = :binary.match(html, "A dietary survey")
      assert p1 < p2
    end

    test "a term in no finding or abstract shows the honest empty state", %{
      conn: conn,
      condition: condition
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")
      html = search(view, "zzqnope")

      # (apostrophe/em-dash are HTML-escaped in the render — assert clean ASCII)
      assert html =~ "open papers on PubMed to check"
      refute html =~ "Dietary fiber is associated with remission"
    end

    test "composes with the verification chips (a contradicted-only match is gated)", %{
      conn: conn,
      condition: condition
    } do
      # A paper whose ONLY finding is contradicted — hidden under the default filter.
      {:ok, _} = Literature.upsert_study(%{pmid: 60_003, title: "Zinc and flares", journal: "Gut"})

      mine_fact(condition, 60_003, %{
        fact_id: "zn1",
        text: "Zincium intake worsened flare duration.",
        label: "contradicted",
        license: "non_commercial",
        study_design: "cohort"
      })

      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      # Matched, but filtered out while Contradicted is off.
      html = search(view, "zincium")
      assert html =~ "none under the current verification filters"
      refute html =~ "Zinc and flares"

      # Toggling Contradicted on reveals it (re-filters the loaded results, no re-query).
      revealed =
        view
        |> element(~s(button[phx-click="toggle_label"][phx-value-label="contradicted"]))
        |> render_click()

      assert revealed =~ "Zinc and flares"
    end

    test "clearing the query returns to the grouped browse view", %{
      conn: conn,
      condition: condition
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      search(view, "fiber")
      cleared = search(view, "")

      # Browse mode restores the research-type grouping.
      assert cleared =~ "Randomized &amp; controlled trials"
    end
  end

  describe "global (all-research) mode on the landing" do
    setup %{condition: condition} do
      # An abstract-only match: the term is in the abstract, not the finding.
      {:ok, _} =
        Literature.upsert_study(%{
          pmid: 55_010,
          title: "Zinc survey",
          abstract: "A survey mentioning fiber in passing.",
          journal: "J Nutr"
        })

      mine_fact(condition, 55_010, %{
        fact_id: "ab1",
        text: "Zinc intake was measured.",
        license: "non_commercial",
        study_design: "cohort"
      })

      # Plain REFRESH — CONCURRENTLY can't run in the test transaction.
      Repo.query!("REFRESH MATERIALIZED VIEW research_search")
      :ok
    end

    test "toggles to All research and renders one card per paper with condition + label", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research")

      view |> element(~s(button[phx-value-mode="papers"])) |> render_click()
      html = view |> element("#research-search-form") |> render_change(%{"q" => "fiber"})

      # (The matched term "fiber" is wrapped in <mark>, so assert on non-term spans.)
      # Finding-matches from the UC papers, each carrying the condition chip.
      assert html =~ "Curcumin in UC"
      assert html =~ "is associated with remission"
      assert html =~ "Ulcerative Colitis"
      assert html =~ "Matched in a finding"
      # The 55002 fiber hit is a contradicted finding — shown labelled, not laundered.
      assert html =~ "contradicted"
      # The abstract-only paper surfaces with the abstract cue.
      assert html =~ "Zinc survey"
      assert html =~ "Matched in abstract"
    end

    test "toggling back to Conditions restores the catalog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research")

      view |> element(~s(button[phx-value-mode="papers"])) |> render_click()
      html = view |> element(~s(button[phx-value-mode="conditions"])) |> render_click()

      assert html =~ "Ulcerative Colitis"
      assert html =~ "studies"
    end

    test "a term that is a tracked mined condition leads with a Browse shortcut", %{
      conn: conn,
      condition: condition
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research")

      view |> element(~s(button[phx-value-mode="papers"])) |> render_click()
      html = view |> element("#research-search-form") |> render_change(%{"q" => "ulcerative colitis"})

      assert html =~ "Tracked condition"
      assert html =~ "Browse Ulcerative Colitis"
      # Deep-links to the curated condition page, above the paper cards.
      assert has_element?(view, ~s(a[href="/nutritionist/research/#{condition.id}"]))
    end
  end

  describe "suggested-note persistence (My notes)" do
    test "saving a fact toggles state and lands in My notes", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist,
      open_study: study
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      assert ResearchNotes.saved_claim_keys(nutritionist.id, condition.id) == MapSet.new()

      save = element(view, ~s(button[phx-click="toggle_save"][phx-value-claim_id="fx1"]))
      assert render(save) =~ "Save"
      render_click(save)

      keys = ResearchNotes.saved_claim_keys(nutritionist.id, condition.id)
      assert MapSet.member?(keys, {study.id, "fx1"})
      assert render(element(view, ~s(button[phx-value-claim_id="fx1"]))) =~ "Saved"

      {:ok, _notes_view, notes_html} = live(conn, ~p"/nutritionist/research/notes")
      assert notes_html =~ "Dietary fiber is associated with remission"
      assert notes_html =~ "1 saved note"

      render_click(element(view, ~s(button[phx-value-claim_id="fx1"])))
      assert ResearchNotes.saved_claim_keys(nutritionist.id, condition.id) == MapSet.new()
    end

    test "writing a custom note saves it under the condition", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist,
      open_study: study
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      view
      |> element(~s(button[phx-click="compose_note"][phx-value-study_id="#{study.id}"]))
      |> render_click()

      view
      |> form(~s(form[phx-submit="save_custom"]), %{
        "study_id" => study.id,
        "body" => "Call the client."
      })
      |> render_submit()

      assert [note] = ResearchNotes.list_for_user(nutritionist.id)
      assert note.kind == "custom"
      assert note.body == "Call the client."
      assert note.condition_id == condition.id
    end

    test "My notes page can delete a note", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist,
      open_study: study
    } do
      {:ok, _} =
        ResearchNotes.create_custom(nutritionist.id, %{
          condition_id: condition.id,
          study_id: study.id,
          body: "To delete."
        })

      {:ok, view, html} = live(conn, ~p"/nutritionist/research/notes")
      assert html =~ "To delete."

      view |> element(~s(button[phx-click="delete_note"])) |> render_click()

      assert ResearchNotes.list_for_user(nutritionist.id) == []
      refute render(view) =~ "To delete."
    end

    test "My notes page filters to a single condition via ?condition_id", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist,
      open_study: study
    } do
      {:ok, other} = Mehungry.Health.create_condition(%{name: "Gout"})

      {:ok, _} =
        ResearchNotes.create_custom(nutritionist.id, %{
          condition_id: condition.id,
          study_id: study.id,
          body: "Colitis note."
        })

      {:ok, _} =
        ResearchNotes.create_custom(nutritionist.id, %{condition_id: other.id, body: "Gout note."})

      {:ok, _v, all_html} = live(conn, ~p"/nutritionist/research/notes")
      assert all_html =~ "Colitis note."
      assert all_html =~ "Gout note."

      {:ok, _v, filtered} = live(conn, ~p"/nutritionist/research/notes?condition_id=#{condition.id}")
      assert filtered =~ "Colitis note."
      refute filtered =~ "Gout note."
      assert filtered =~ condition.name

      {:ok, empty} = Mehungry.Health.create_condition(%{name: "Histamine Intolerance"})
      {:ok, _v, empty_html} = live(conn, ~p"/nutritionist/research/notes?condition_id=#{empty.id}")
      assert empty_html =~ "No notes saved for Histamine Intolerance"
      assert empty_html =~ "Histamine Intolerance research"
    end
  end

  # ── Legacy full-text reader shell (unchanged ResearchPaper LV). New miner
  # publications link out; the reader still serves any positively-verified,
  # reusable-licensed StudyFullText on record (here forced displayable). ─────────
  describe "full-text paper reader (legacy shell)" do
    setup %{condition: condition} do
      study = add_displayable_full_text_study(condition)
      %{study: study}
    end

    test "renders sections with anchors and highlights a claim span", %{
      conn: conn,
      condition: condition,
      study: study
    } do
      {:ok, _view, html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      assert html =~ ~s(id="sec-sec-a")
      assert html =~ ~s(id="par-par-a")
      assert html =~ "Introduction"
      assert html =~ ~r/<mark[^>]*>\s*Fiber\s*<\/mark>/
      assert html =~ "improves remission"
    end

    test "the reader's notes widget saves a suggested note", %{
      conn: conn,
      condition: condition,
      study: study,
      nutritionist: nutritionist
    } do
      {:ok, view, _html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      assert has_element?(view, "details:not([open]) > summary", "Suggested notes (1)")

      view
      |> element(~s(button[phx-click="toggle_save"][phx-value-claim_id="k1"]))
      |> render_click()

      keys = ResearchNotes.saved_claim_keys(nutritionist.id, condition.id)
      assert MapSet.member?(keys, {study.id, "k1"})
    end

    test "the reader redirects when the study has no full text", %{conn: conn, condition: condition} do
      {:ok, no_ft} = Literature.upsert_study(%{pmid: 55_777, title: "Abstract only"})

      %StudyCondition{}
      |> StudyCondition.changeset(%{study_id: no_ft.id, condition_id: condition.id, search_term: "x"})
      |> Repo.insert!()

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{no_ft.id}")

      assert to == "/nutritionist/research/#{condition.id}"
    end
  end

  # A study with a full-text section outline + one highlightable claim span,
  # forced displayable (verified + reusable licence) so the reader shell serves it.
  defp add_displayable_full_text_study(condition) do
    {:ok, study} =
      Literature.upsert_study(%{pmid: 55_500, title: "Full-text fiber trial", journal: "Gut"})

    %StudyCondition{}
    |> StudyCondition.changeset(%{study_id: study.id, condition_id: condition.id, search_term: "diet"})
    |> Repo.insert!()

    {:ok, _} =
      Literature.store_analysis_response(%{
        "run" => %{"synthesis_version" => "0.1.0"},
        "papers" => [
          %{
            "pmid" => "55500",
            "status" => "included",
            "title" => "Full-text fiber trial",
            "source_type" => "open_access",
            "study_design" => "cohort"
          }
        ],
        "paper_claims" => [
          %{
            "pmid" => "55500",
            "paper_title" => "Full-text fiber trial",
            "sections" => [
              %{
                "section_id" => "sec-a",
                "index" => 0,
                "title" => "Introduction",
                "start_char" => 0,
                "end_char" => 41,
                "paragraphs" => [
                  %{
                    "paragraph_id" => "par-a",
                    "start_char" => 0,
                    "end_char" => 41,
                    "text" => "Fiber improves remission in colitis here."
                  }
                ]
              }
            ],
            "claims_list" => [
              %{
                "claim_id" => "k1",
                "predicate" => "improves",
                "polarity" => "positive",
                "certainty" => "asserted",
                "subject_label" => "Dietary fiber",
                "object_label" => "Remission",
                "evidence" => [
                  %{
                    "paragraph_id" => "par-a",
                    "start_char" => 0,
                    "end_char" => 5,
                    "quoted_text" => "Fiber"
                  }
                ]
              }
            ]
          }
        ],
        "warnings" => []
      })

    # The reader only serves positively-verified, reusable-licensed full text; the
    # dormant extractor ingest leaves rows pending_review, so force it here.
    Literature.get_full_text(study.id)
    |> Ecto.Changeset.change(%{
      full_text_displayable: true,
      integrity_status: "verified",
      license: "cc-by"
    })
    |> Repo.update!()

    study
  end
end
