defmodule MehungryWeb.ProfessionalLive.SpeciesEnrichmentReviewTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesEnrichmentRuns, as: Runs

  @admin_email Application.compile_env(:mehungry, :admin_email)

  # Stub the bundled-CSV seam so the crosswalk suggester has a deterministic item list.
  defmodule FaostatStub do
    def load_rows do
      {:ok, [%{item_code: "515", area: "China", value_tonnes: 100.0, year: 2022, item: "Apples"}]}
    end
  end

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})

    Application.put_env(:mehungry, :faostat_client, FaostatStub)
    on_exit(fn -> Application.delete_env(:mehungry, :faostat_client) end)

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Acerola",
        "scientific_name" => "Malpighia emarginata"
      })

    %{conn: log_in_user(conn, admin), species: species}
  end

  test "renders the enrichment page with an empty batch", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/species-enrichment")
    assert html =~ "Species enrichment"
    assert html =~ "Enrich all species"
  end

  test "the enrich_all trigger fans out a batch and streams rows", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/species-enrichment")

    view |> element("button[phx-click='enrich_all']") |> render_click()
    # The trigger runs via start_async; await it so the batch is created + streamed.
    assert render_async(view) =~ "Acerola"

    # A batch now exists with the species streamed as a pending row.
    batch_id = Runs.latest_batch_id()
    assert batch_id
    assert [row] = Runs.list_batch_rows(batch_id)

    # Simulate the worker finishing it — the live view patches the row to "completed".
    Runs.mark_completed(row.id, %{wikidata: 3, faostat: 1})
    assert render(view) =~ "completed"
  end

  test "promote-all surfaces pending Wikidata facts", %{conn: conn, species: species} do
    Food.record_species_wikidata_facts(species.id, %{qid: "Q89", origin_region: "Central Asia"})

    {:ok, view, _html} = live(conn, ~p"/professional/species-enrichment")
    assert render(view) =~ "Promote all pending"

    view |> element("button[phx-click='promote_all']") |> render_click()

    assert Food.promoted_species_facts_for_species(species.id)["origin_region"].value_text ==
             "Central Asia"
  end

  test "the crosswalk section lists species with the current code", %{conn: conn} do
    {:ok, apple} = Food.create_foundemental_species(%{"name" => "Apple"})
    apple |> Ecto.Changeset.change(%{faostat_item_code: "515"}) |> Mehungry.Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/professional/species-enrichment")
    assert html =~ "FAOSTAT crosswalk"
    assert html =~ "value=\"515\""
  end

  test "Run suggester shows a fuzzy match per species", %{conn: conn} do
    {:ok, _apple} = Food.create_foundemental_species(%{"name" => "Apple"})

    {:ok, view, _html} = live(conn, ~p"/professional/species-enrichment")
    html = view |> element("button[phx-click='suggest_faostat']") |> render_click()

    # Apple → Apples is a near-exact match surfaced with its item name.
    assert html =~ "Apples"
    assert html =~ "Apply"
  end

  test "saving a code persists it and clearing unsets it", %{conn: conn, species: species} do
    {:ok, view, _html} = live(conn, ~p"/professional/species-enrichment")

    view
    |> form("form[phx-submit='save_faostat_code']", %{"species_id" => species.id, "code" => "426"})
    |> render_submit()

    assert Food.get_foundemental_species!(species.id).faostat_item_code == "426"

    view
    |> form("form[phx-submit='save_faostat_code']", %{"species_id" => species.id, "code" => "  "})
    |> render_submit()

    assert Food.get_foundemental_species!(species.id).faostat_item_code == nil
  end

  test "Apply writes the suggested code", %{conn: conn} do
    {:ok, apple} = Food.create_foundemental_species(%{"name" => "Apple"})

    {:ok, view, _html} = live(conn, ~p"/professional/species-enrichment")
    view |> element("button[phx-click='suggest_faostat']") |> render_click()
    view |> element("button[phx-value-species-id='#{apple.id}']") |> render_click()

    assert Food.get_foundemental_species!(apple.id).faostat_item_code == "515"
  end

  test "redirects a non-admin", %{conn: _conn} do
    plain = user_fixture()
    conn = log_in_user(build_conn(), plain)
    assert {:error, {:redirect, _}} = live(conn, ~p"/professional/species-enrichment")
  end
end
