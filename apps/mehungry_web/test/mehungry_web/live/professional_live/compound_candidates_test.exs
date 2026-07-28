defmodule MehungryWeb.ProfessionalLive.CompoundCandidatesTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.CandidateDerivationRun
  alias Mehungry.Food.CandidateDerivationRuns
  alias Mehungry.Food.CompoundCandidates
  alias Mehungry.ObanWorkers.CompoundCandidateDerivationWorker, as: Worker

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

  test "renders the derive controls and the pending candidate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/compound-candidates")

    assert html =~ "Compound Candidates"
    assert html =~ "Derive candidates"
    assert html =~ "spinach"
    assert html =~ "Oxalate"
    assert html =~ "Idle"
  end

  test "Promote writes a curated relationship and drops the row", %{
    conn: conn,
    candidate: candidate,
    spinach: spinach
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

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
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{candidate.id}']")
    |> render_click()

    refute render(view) =~ "Oxalate"
    assert Food.list_compound_relationships(spinach.id) == []
    assert Food.get_candidate!(candidate.id).status == "rejected"
  end

  test "Derive opens a run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

    assert CandidateDerivationRuns.latest_run() == nil

    html = view |> element("button", "Derive candidates") |> render_click()

    assert html =~ "Derivation started"
    assert CandidateDerivationRuns.latest_run()
    assert_enqueued(worker: Worker)
  end

  test "a broadcast run update moves the progress bar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

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

  test "non-admin is redirected away", %{} do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/compound-candidates")
  end
end
