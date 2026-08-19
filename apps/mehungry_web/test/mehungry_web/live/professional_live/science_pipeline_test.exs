defmodule MehungryWeb.ProfessionalLive.SciencePipelineTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.CandidateDerivationRun
  alias Mehungry.Food.CandidateDerivationRuns
  alias Mehungry.Food.CompoundCandidates
  alias Mehungry.Literature.AnnotationRuns
  alias Mehungry.Literature.CrawlRuns

  alias Mehungry.ObanWorkers.CompoundCandidateDerivationWorker
  alias Mehungry.ObanWorkers.LiteratureCrawlWorker
  alias Mehungry.ObanWorkers.PubTatorAnnotationWorker

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    {:ok, candidate} =
      CompoundCandidates.import_manual_candidate(species.id, oxalate.id, %{notes: "expert"})

    %{conn: conn, spinach: spinach, species: species, oxalate: oxalate, candidate: candidate}
  end

  test "renders the three stage controls and the pending candidate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/science")

    assert html =~ "Science Pipeline"
    assert html =~ "Run crawl"
    assert html =~ "Run annotation"
    assert html =~ "Derive candidates"
    assert html =~ "Spinach"
    assert html =~ "Oxalate"

    # Steps P & 0 are gone.
    refute html =~ "Run parsing"
    refute html =~ "Run resolution"
  end

  test "Run crawl opens a run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    html = view |> element("button", "Run crawl") |> render_click()

    assert html =~ "Crawl started"
    assert CrawlRuns.latest_run()
    assert_enqueued(worker: LiteratureCrawlWorker)
  end

  test "Run annotation opens a run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    html = view |> element("button", "Run annotation") |> render_click()

    assert html =~ "Annotation started"
    assert AnnotationRuns.latest_run()
    assert_enqueued(worker: PubTatorAnnotationWorker)
  end

  test "Derive opens a run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    assert CandidateDerivationRuns.latest_run() == nil

    html = view |> element("button", "Derive candidates") |> render_click()

    assert html =~ "Derivation started"
    assert CandidateDerivationRuns.latest_run()
    assert_enqueued(worker: CompoundCandidateDerivationWorker)
  end

  test "Promote writes a curated relationship and drops the row", %{
    conn: conn,
    candidate: candidate,
    species: species
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    assert render(view) =~ "Oxalate"

    view
    |> element("button[phx-click='promote'][phx-value-id='#{candidate.id}']")
    |> render_click()

    refute render(view) =~ "Oxalate"
    assert [rel] = Mehungry.Food.SpeciesCompounds.list_species_relationships(species.id)
    assert rel.source == "manual"
    assert Food.get_candidate!(candidate.id).status == "promoted"
  end

  test "Reject drops the row and writes no fact", %{
    conn: conn,
    candidate: candidate,
    species: species
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{candidate.id}']")
    |> render_click()

    refute render(view) =~ "Oxalate"
    assert Mehungry.Food.SpeciesCompounds.list_species_relationships(species.id) == []
    assert Food.get_candidate!(candidate.id).status == "rejected"
  end

  test "a derivation broadcast moves the bar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    run = %CandidateDerivationRun{status: "processing", processed: 3, total: 4, promoted_count: 1}

    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      CandidateDerivationRuns.topic(),
      {:candidate_derivation_run, run}
    )

    html = render(view)
    assert html =~ "3 / 4 (75%)"
    assert html =~ "Deriving…"
  end

  test "shows read-only full-text extraction status (runs in the external local-AI service)", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, ~p"/professional/science")
    assert html =~ "Full-text extraction"
    assert html =~ "local-AI service"
    assert html =~ "pending review"
  end

  test "non-admin is redirected away" do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/science")
  end
end
