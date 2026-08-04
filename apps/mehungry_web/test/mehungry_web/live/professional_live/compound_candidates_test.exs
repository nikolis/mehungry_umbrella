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
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.ObanWorkers.CompoundCandidateDerivationWorker, as: Worker

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

  test "renders the derive controls and the pending candidate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/compound-candidates")

    assert html =~ "Compound Candidates"
    assert html =~ "Derive candidates"
    assert html =~ "Spinach"
    assert html =~ "Oxalate"
    assert html =~ "Idle"
  end

  test "Promote writes a species fact and drops the row", %{
    conn: conn,
    candidate: candidate,
    species: species
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

    assert render(view) =~ "Oxalate"

    view
    |> element("button[phx-click='promote'][phx-value-id='#{candidate.id}']")
    |> render_click()

    assert [rel] = SpeciesCompounds.list_species_relationships(species.id)
    assert rel.source == "manual"
    assert Food.get_candidate!(candidate.id).status == "promoted"
  end

  test "Reject drops the row and writes no fact", %{
    conn: conn,
    candidate: candidate,
    species: species
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{candidate.id}']")
    |> render_click()

    # The candidate leaves the pending queue (checked via the context — "Oxalate"
    # also appears in the measurement form's compound dropdown).
    assert Food.list_pending_candidates() == []
    assert SpeciesCompounds.list_species_relationships(species.id) == []
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

  test "curated facts list a promoted species fact and Undo removes it", %{
    conn: conn,
    candidate: candidate,
    species: species
  } do
    {:ok, _} = Food.promote_candidate(candidate.id)
    {:ok, view, html} = live(conn, ~p"/professional/compound-candidates")

    assert html =~ "Curated facts"
    assert html =~ "Oxalate"
    [rel] = SpeciesCompounds.list_species_relationships(species.id)

    view
    |> element("button[phx-click='undo'][phx-value-id='#{rel.id}']")
    |> render_click()

    assert SpeciesCompounds.list_species_relationships(species.id) == []
    assert Food.get_candidate!(candidate.id).status == "rejected"
  end

  test "Purge non-dietary deletes blocklisted facts", %{conn: conn, species: species} do
    {:ok, dpph} = Food.upsert_compound(%{name: "DPPH", compound_type: "other"})
    {:ok, cand} = Food.import_manual_candidate(species.id, dpph.id, %{})
    {:ok, _} = Food.promote_candidate(cand.id)

    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")
    view |> element("button", "Purge non-dietary") |> render_click()

    assert Enum.filter(
             SpeciesCompounds.list_species_relationships(species.id),
             &(&1.compound_id == dpph.id)
           ) == []
  end

  test "Add measurement records it and re-scores the species candidate", %{
    conn: conn,
    spinach: spinach,
    species: species,
    oxalate: oxalate
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-candidates")

    view
    |> form("form[phx-submit=add_measurement]",
      measurement: %{
        ingredient_id: spinach.id,
        compound_id: oxalate.id,
        value: "750",
        unit: "mg/100g",
        preparation_method: "Raw",
        analytical_method: "HPLC",
        extraction_method: "manual"
      }
    )
    |> render_submit()

    assert [m] = Food.list_measurements_for_ingredient(spinach.id)
    assert m.value == 750.0
    assert m.compound_id == oxalate.id

    # The species candidate now carries the measurement as evidence.
    candidate =
      Food.list_candidates_for_species(species.id)
      |> Enum.find(&(&1.compound_id == oxalate.id))

    assert candidate
    assert "measurement" in candidate.sources
  end

  test "accepts an extracted measurement candidate → records a measurement", %{
    conn: conn,
    species: species,
    oxalate: oxalate,
    spinach: spinach
  } do
    {:ok, study} =
      Mehungry.Literature.upsert_study(%{
        pmid: 55_555,
        title: "s",
        retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, cand} =
      Food.upsert_measurement_candidate(%{
        foundemental_species_id: species.id,
        compound_id: oxalate.id,
        study_id: study.id,
        value: 750.0,
        unit: "mg/100 g",
        analytical_method: "HPLC",
        score: 0.9
      })

    {:ok, view, html} = live(conn, ~p"/professional/compound-candidates")
    assert html =~ "Measurement candidates"

    view
    |> element("button[phx-click='accept_measurement'][phx-value-id='#{cand.id}']")
    |> render_click()

    assert [m] = Food.list_measurements_for_ingredient(spinach.id)
    assert m.value == 750.0
    assert m.compound_id == oxalate.id
  end
end
