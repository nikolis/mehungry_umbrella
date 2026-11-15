defmodule MehungryWeb.ProfessionalLive.FactMiningPipelineTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.FactMining.SpeciesFactMiningRuns, as: Runs

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Acerola",
        "scientific_name" => "Malpighia emarginata"
      })

    on_exit(fn ->
      Application.delete_env(:mehungry, :fact_miner_stub_reachable)
      Application.delete_env(:mehungry, :fact_miner_stub_last_query)
    end)

    %{conn: log_in_user(conn, admin), species: species}
  end

  test "renders the fact-mining page with the mine-one form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/compound-pipeline")
    assert html =~ "Fact mining"
    assert html =~ "Mine species"
    assert html =~ "Prompt sent to the miner"
    refute html =~ "Mine all species"
  end

  test "picking a species pre-fills the default prompt", %{conn: conn, species: species} do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-pipeline")

    html =
      view
      |> element("select[name='species_id']")
      |> render_change(%{"species_id" => to_string(species.id)})

    assert html =~ "tell me all the facts about Acerola (Malpighia emarginata)"
  end

  test "submitting the form mines one species with the edited prompt", %{
    conn: conn,
    species: species
  } do
    Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)
    {:ok, view, _html} = live(conn, ~p"/professional/compound-pipeline")

    view
    |> form("form[phx-submit='mine_species']", %{
      "species_id" => to_string(species.id),
      "query" => "just the vitamin C facts"
    })
    |> render_submit()

    assert render_async(view) =~ "Mining started"

    batch_id = Runs.latest_batch_id()
    assert [%{foundemental_species_id: sid, query: "just the vitamin C facts"}] =
             Runs.list_batch_rows(batch_id)

    assert sid == species.id
  end

  test "a terminal broadcast patches a streamed species row", %{conn: conn} do
    Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)
    {:ok, batch_id} = Runs.mine_all_species()
    [row] = Runs.list_batch_rows(batch_id)

    # Mount after the batch exists so the row is streamed, then simulate the worker
    # finishing it — the live view should patch the row to "completed".
    {:ok, view, _html} = live(conn, ~p"/professional/compound-pipeline")
    Runs.mark_completed(row.id, %{total: 2, verified: 2, contradicted: 0})

    assert render(view) =~ "completed"
  end

  test "saving the connection form persists the miner URL + token", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-pipeline")

    view
    |> form("form[phx-submit='save_connection']", %{
      "settings" => %{"base_url" => "http://miner.test:9000", "auth_token" => "jwt-123"}
    })
    |> render_submit()

    settings = Mehungry.FactMining.get_settings()
    assert settings.base_url == "http://miner.test:9000"
    assert settings.auth_token == "jwt-123"
    assert {"http://miner.test:9000", "jwt-123"} == Mehungry.FactMining.connection()
  end

  test "rejects a non-http base URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/compound-pipeline")

    html =
      view
      |> form("form[phx-submit='save_connection']", %{
        "settings" => %{"base_url" => "not-a-url"}
      })
      |> render_submit()

    assert html =~ "must be a valid http(s) URL"
    assert Mehungry.FactMining.get_settings() == nil
  end

  test "redirects a non-admin", %{conn: _conn} do
    plain = user_fixture()
    conn = log_in_user(build_conn(), plain)
    assert {:error, {:redirect, _}} = live(conn, ~p"/professional/compound-pipeline")
  end
end
