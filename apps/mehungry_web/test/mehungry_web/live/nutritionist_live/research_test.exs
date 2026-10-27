defmodule MehungryWeb.NutritionistLive.ResearchTest do
  @moduledoc """
  Smoke tests for the nutritionist research search engine: the catalog landing
  (search by condition) and the per-condition results page (research grouped by
  type with highlighted, source-linked findings).
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Literature, Professionals, Subscriptions}
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

    {:ok, study} =
      Literature.upsert_study(%{
        pmid: 55_001,
        title: "Dietary fiber in ulcerative colitis",
        journal: "Gut",
        authors: ["Smith J", "Doe A", "Roe B"],
        citation_status: "MEDLINE"
      })

    %StudyCondition{}
    |> StudyCondition.changeset(%{
      study_id: study.id,
      condition_id: condition.id,
      search_term: "Ulcerative Colitis diet"
    })
    |> Repo.insert!()

    {:ok, _} =
      Literature.store_analysis_response(%{
        "run" => %{"synthesis_version" => "0.1.0"},
        "papers" => [
          %{
            "pmid" => "55001",
            "status" => "included",
            "title" => "Dietary fiber in ulcerative colitis",
            "source_type" => "open_access",
            "study_design" => "randomized_controlled_trial",
            "publication_year" => 2022,
            "sample_size" => 120
          }
        ],
        "paper_claims" => [
          %{
            "pmid" => "55001",
            "paper_title" => "Dietary fiber in ulcerative colitis",
            "claims_list" => [
              %{
                "claim_id" => "k1",
                "predicate" => "improves",
                "polarity" => "positive",
                "certainty" => "asserted",
                "subject_label" => "Dietary fiber",
                "object_label" => "Remission",
                "evidence" => [%{"quoted_text" => "fiber improved remission rates"}]
              }
            ]
          }
        ],
        "warnings" => []
      })

    %{conn: log_in_user(conn, nutritionist), condition: condition, nutritionist: nutritionist}
  end

  test "catalog lists conditions with research and filters by search", %{
    conn: conn,
    condition: condition
  } do
    {:ok, view, html} = live(conn, ~p"/nutritionist/research")

    assert html =~ "Ulcerative Colitis"
    assert html =~ "1 study"

    link = ~s(a[href="/nutritionist/research/#{condition.id}"])
    search = fn q -> view |> element("#research-search-form") |> render_change(%{"q" => q}) end

    # Case-insensitive substring match keeps the catalog entry.
    search.("coli")
    assert has_element?(view, link)
    # A non-matching term empties the catalog (the placeholder still names a condition,
    # so assert on the result link, not loose page text).
    search.("zzz-nope")
    refute has_element?(view, link)
  end

  test "results page groups by research type and highlights source-linked findings", %{
    conn: conn,
    condition: condition
  } do
    {:ok, _view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

    # Grouped under the strongest-evidence bucket.
    assert html =~ "Randomized &amp; controlled trials"
    # Publication metadata.
    assert html =~ "Dietary fiber in ulcerative colitis"
    assert html =~ "Gut"
    assert html =~ "n = 120"
    assert html =~ "Smith J"
    # Journal-authority chip (public-domain MEDLINE indexing signal).
    assert html =~ "MEDLINE-indexed"
    # The highlighted finding + its verbatim evidence quote.
    assert html =~ "Dietary fiber"
    assert html =~ "Remission"
    assert html =~ "fiber improved remission rates"
    # Linked to the source on PubMed.
    assert html =~ "https://pubmed.ncbi.nlm.nih.gov/55001/"
  end

  test "a claim curated wrong/ignore is hidden from the results", %{
    conn: conn,
    condition: condition
  } do
    study = Literature.get_study_by_pmid(55_001)
    {:ok, _} = Literature.set_claim_position(study.id, "k1", "ignore")

    {:ok, _view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

    refute html =~ "fiber improved remission rates"
    assert html =~ "No highlighted findings for this paper."
  end

  test "suggested notes are behind a per-card toggle", %{conn: conn, condition: condition} do
    {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")
    # Native <details>/<summary> disclosure — collapsed by default (no `open`),
    # so the notes start hidden. The note markup is server-rendered inside.
    assert has_element?(view, "details:not([open]) > summary", "Suggested notes (1)")
  end

  describe "suggested-note persistence (My notes)" do
    test "saving a suggested note toggles state and lands in My notes", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")
      study = Literature.get_study_by_pmid(55_001)

      # Not saved yet.
      assert ResearchNotes.saved_claim_keys(nutritionist.id, condition.id) == MapSet.new()

      save = element(view, ~s(button[phx-click="toggle_save"][phx-value-claim_id="k1"]))
      assert render(save) =~ "Save"
      render_click(save)

      # Persisted as a suggested note, keyed on {study, claim}.
      keys = ResearchNotes.saved_claim_keys(nutritionist.id, condition.id)
      assert MapSet.member?(keys, {study.id, "k1"})
      # Button now reflects the saved state.
      assert render(element(view, ~s(button[phx-value-claim_id="k1"]))) =~ "Saved"

      # Shows up on the My notes page.
      {:ok, _notes_view, notes_html} = live(conn, ~p"/nutritionist/research/notes")
      assert notes_html =~ "Dietary fiber — improves — Remission"
      assert notes_html =~ "1 saved note"

      # Toggling again removes it.
      render_click(element(view, ~s(button[phx-value-claim_id="k1"])))
      assert ResearchNotes.saved_claim_keys(nutritionist.id, condition.id) == MapSet.new()
    end

    test "writing a custom note saves it under the condition", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")
      study = Literature.get_study_by_pmid(55_001)

      view
      |> element(~s(button[phx-click="compose_note"][phx-value-study_id="#{study.id}"]))
      |> render_click()

      view
      |> form(~s(form[phx-submit="save_custom"]), %{"study_id" => study.id, "body" => "Call the client."})
      |> render_submit()

      assert [note] = ResearchNotes.list_for_user(nutritionist.id)
      assert note.kind == "custom"
      assert note.body == "Call the client."
      assert note.condition_id == condition.id
    end

    test "My notes page can delete a note", %{
      conn: conn,
      condition: condition,
      nutritionist: nutritionist
    } do
      study = Literature.get_study_by_pmid(55_001)

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
  end

  describe "full-text paper (section outline + reader)" do
    setup %{condition: condition} do
      study = add_full_text_study(condition)
      %{study: study}
    end

    test "results card lists section titles that deep-link into the reader", %{
      conn: conn,
      condition: condition,
      study: study
    } do
      {:ok, _view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      assert html =~ "Read full text"
      assert html =~ "Introduction"
      assert html =~ "/nutritionist/research/#{condition.id}/paper/#{study.id}#sec-sec-a"
    end

    test "a suggested note links 'Open in text' to its evidence paragraph in the reader", %{
      conn: conn,
      condition: condition,
      study: study
    } do
      {:ok, _view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      assert html =~ "Open in text"
      # Deep-links to the reader at the claim's first evidence paragraph (#par-…),
      # not out to PubMed.
      assert html =~ "/nutritionist/research/#{condition.id}/paper/#{study.id}#par-par-a"
    end

    test "the reader renders sections with anchors and highlights a claim span", %{
      conn: conn,
      condition: condition,
      study: study
    } do
      {:ok, _view, html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      assert html =~ ~s(id="sec-sec-a")
      assert html =~ ~s(id="par-par-a")
      assert html =~ "Introduction"
      # The claim's evidence span ("Fiber") is wrapped in a <mark>.
      assert html =~ ~r/<mark[^>]*>\s*Fiber\s*<\/mark>/
      # The rest of the paragraph remains as plain text.
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

      # The suggested notes are a closed-by-default, expandable list in the widget.
      assert has_element?(view, "details:not([open]) > summary", "Suggested notes (1)")

      view
      |> element(~s(button[phx-click="toggle_save"][phx-value-claim_id="k1"]))
      |> render_click()

      keys = ResearchNotes.saved_claim_keys(nutritionist.id, condition.id)
      assert MapSet.member?(keys, {study.id, "k1"})
    end

    test "writing a note from a highlighted passage saves the sub-text + title", %{
      conn: conn,
      condition: condition,
      study: study,
      nutritionist: nutritionist
    } do
      {:ok, view, _html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      # Enter selection mode: the article advertises note mode to the JS hook.
      view |> element(~s(button[phx-click="start_note"])) |> render_click()
      assert render(view) =~ ~s(data-note-mode="true")

      # The NoteSelection hook reports the highlighted passage + its anchors.
      view
      |> element("#reader-article")
      |> render_hook("select_passage", %{
        "text" => "Fiber improves remission",
        "paragraph_id" => "par-a",
        "section_id" => "sec-a"
      })

      # The captured sub-text is previewed in the form.
      assert render(view) =~ "Fiber improves remission"

      view
      |> form(~s(form[phx-submit="save_custom"]), %{"title" => "Dose worth checking"})
      |> render_submit()

      assert [note] = ResearchNotes.list_for_user(nutritionist.id)
      assert note.kind == "custom"
      assert note.body == "Dose worth checking"
      assert note.quoted_text == "Fiber improves remission"
      assert note.paragraph_id == "par-a"
      assert note.condition_id == condition.id

      # The note now shows in the widget's "Your notes" list, and can be deleted there.
      html = render(view)
      assert html =~ "Your notes (1)"
      assert html =~ "Dose worth checking"

      view |> element(~s(button[phx-click="delete_note"])) |> render_click()
      assert ResearchNotes.list_for_user(nutritionist.id) == []
      refute render(view) =~ "Dose worth checking"
    end

    test "a custom note's marked passage is highlighted inline in the reader", %{
      conn: conn,
      condition: condition,
      study: study,
      nutritionist: nutritionist
    } do
      {:ok, _} =
        ResearchNotes.create_custom(nutritionist.id, %{
          condition_id: condition.id,
          study_id: study.id,
          body: "Check this",
          quoted_text: "improves remission",
          paragraph_id: "par-a",
          section_id: "sec-a"
        })

      {:ok, _view, html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      # The marked passage is wrapped in a <mark> with the note (accent) tint,
      # alongside the existing claim highlight ("Fiber").
      assert html =~ ~r/<mark[^>]*bg-accent-400\/30[^>]*>improves remission<\/mark>/
      assert html =~ ~r/<mark[^>]*>\s*Fiber\s*<\/mark>/

      # The note's title in the widget links to its marked paragraph.
      assert html =~ ~r/<a [^>]*href="#par-par-a"[^>]*>\s*Check this\s*<\/a>/
    end

    test "the widget lists the user's pre-existing notes for this paper on load", %{
      conn: conn,
      condition: condition,
      study: study,
      nutritionist: nutritionist
    } do
      {:ok, _} =
        ResearchNotes.create_custom(nutritionist.id, %{
          condition_id: condition.id,
          study_id: study.id,
          body: "Earlier thought."
        })

      {:ok, _view, html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      assert html =~ "Your notes (1)"
      assert html =~ "Earlier thought."
    end

    test "a passage selection outside note mode is ignored", %{
      conn: conn,
      condition: condition,
      study: study,
      nutritionist: nutritionist
    } do
      {:ok, view, _html} =
        live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{study.id}")

      view
      |> element("#reader-article")
      |> render_hook("select_passage", %{"text" => "stray", "paragraph_id" => "par-a"})

      refute render(view) =~ "stray"
      assert ResearchNotes.list_for_user(nutritionist.id) == []
    end

    test "the reader redirects when the study has no full text", %{conn: conn, condition: condition} do
      {:ok, no_ft} = Literature.upsert_study(%{pmid: 55_777, title: "Abstract only"})

      %StudyCondition{}
      |> StudyCondition.changeset(%{
        study_id: no_ft.id,
        condition_id: condition.id,
        search_term: "x"
      })
      |> Repo.insert!()

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/nutritionist/research/#{condition.id}/paper/#{no_ft.id}")

      assert to == "/nutritionist/research/#{condition.id}"
    end

    test "the 'Full text' filter hides papers without an open-access outline", %{
      conn: conn,
      condition: condition
    } do
      {:ok, view, html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      # Both the abstract-only base paper and the full-text paper show initially.
      assert html =~ "Dietary fiber in ulcerative colitis"
      assert html =~ "Full-text fiber trial"

      html =
        view
        |> element("button[phx-value-filter=full_text]")
        |> render_click()

      # Only the full-text paper survives the filter.
      assert html =~ "Full-text fiber trial"
      refute html =~ "Dietary fiber in ulcerative colitis"
      assert html =~ "Showing 1 of 2 studies"
    end

    test "offers the sort control with the metadata-based options", %{
      conn: conn,
      condition: condition
    } do
      {:ok, view, _html} = live(conn, ~p"/nutritionist/research/#{condition.id}")

      assert has_element?(view, "select#sort option[value=newest]")
      assert has_element?(view, "select#sort option[value=sample]")
      assert has_element?(view, "select#sort option[value=findings]")

      # Changing the sort is accepted and re-renders.
      assert view
             |> element("form[phx-change=set_sort]")
             |> render_change(%{"sort" => "newest"}) =~ "Full-text fiber trial"
    end
  end

  # A second study under the condition that carries a full-text section outline
  # with one highlightable claim span.
  defp add_full_text_study(condition) do
    {:ok, study} =
      Literature.upsert_study(%{pmid: 55_500, title: "Full-text fiber trial", journal: "Gut"})

    %StudyCondition{}
    |> StudyCondition.changeset(%{
      study_id: study.id,
      condition_id: condition.id,
      search_term: "diet"
    })
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

    study
  end
end
