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
  alias Mehungry.Food.FoodParsingRuns
  alias Mehungry.Food.IdentityResolutionRuns
  alias Mehungry.Food.IngredientFoodParsingRun
  alias Mehungry.Food.IngredientIdentityResolutionRun
  alias Mehungry.Literature.AnnotationRuns
  alias Mehungry.Literature.CrawlRuns

  alias Mehungry.ObanWorkers.CompoundCandidateDerivationWorker
  alias Mehungry.ObanWorkers.IngredientFoodParsingWorker
  alias Mehungry.ObanWorkers.IngredientIdentityResolutionWorker
  alias Mehungry.ObanWorkers.LiteratureCrawlWorker
  alias Mehungry.ObanWorkers.PubTatorAnnotationWorker

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, candidate} =
      CompoundCandidates.import_manual_candidate(spinach.id, oxalate.id, %{notes: "expert"})

    %{conn: conn, spinach: spinach, oxalate: oxalate, candidate: candidate}
  end

  test "renders all four stage controls and the pending candidate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/science")

    assert html =~ "Science Pipeline"
    assert html =~ "Run resolution"
    assert html =~ "Run crawl"
    assert html =~ "Run annotation"
    assert html =~ "Derive candidates"
    assert html =~ "spinach"
    assert html =~ "Oxalate"
  end

  test "Run parsing opens a run and enqueues the worker", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/professional/science")

    assert html =~ "Run parsing"
    assert Food.latest_food_parsing_run() == nil

    html = view |> element("button", "Run parsing") |> render_click()

    assert html =~ "Description parsing started"
    assert Food.latest_food_parsing_run()
    assert_enqueued(worker: IngredientFoodParsingWorker)
  end

  test "a food-parsing broadcast moves the parsing bar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    run = %IngredientFoodParsingRun{status: "processing", processed: 3, total: 4}

    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      FoodParsingRuns.topic(),
      {:food_parsing_run, run}
    )

    html = render(view)
    assert html =~ "3 / 4 (75%)"
    assert html =~ "Parsing…"
  end

  test "Run resolution opens a run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    assert Food.latest_identity_resolution_run() == nil

    html = view |> element("button", "Run resolution") |> render_click()

    assert html =~ "Identity resolution started"
    assert Food.latest_identity_resolution_run()
    assert_enqueued(worker: IngredientIdentityResolutionWorker)
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
    spinach: spinach
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    assert render(view) =~ "Oxalate"

    view
    |> element("button[phx-click='promote'][phx-value-id='#{candidate.id}']")
    |> render_click()

    refute render(view) =~ "Oxalate"
    assert [rel] = Food.list_compound_relationships(spinach.id)
    assert rel.source == "manual"
    assert Food.get_candidate!(candidate.id).status == "promoted"
  end

  test "Reject drops the row and writes no fact", %{
    conn: conn,
    candidate: candidate,
    spinach: spinach
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{candidate.id}']")
    |> render_click()

    refute render(view) =~ "Oxalate"
    assert Food.list_compound_relationships(spinach.id) == []
    assert Food.get_candidate!(candidate.id).status == "rejected"
  end

  test "an identity-resolution broadcast moves the resolution bar (resolved→processed)", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/science")

    run = %IngredientIdentityResolutionRun{status: "processing", resolved: 3, total: 4}

    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      IdentityResolutionRuns.topic(),
      {:identity_resolution_run, run}
    )

    html = render(view)
    assert html =~ "3 / 4 (75%)"
    assert html =~ "Running…"
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

  test "non-admin is redirected away" do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/science")
  end
end
