defmodule MehungryWeb.NutritionistLive.RecordsTest do
  @moduledoc """
  Smoke tests for the client-records roster and the dietary-history CSV import
  flow (upload → preview → confirm).
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo, Subscriptions}
  alias Mehungry.Professionals.DietaryHistory.Importer
  alias Mehungry.Professionals.TutorClientAssignment

  @fixture Path.expand(
             "../../../../../mehungry/test/fixtures/dietary_history_sample.csv",
             __DIR__
           )

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _} =
      Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    client_user = Mehungry.AccountsFixtures.user_fixture()
    client_user = Repo.update!(Ecto.Changeset.change(client_user, name: "Platform Client"))

    Repo.insert!(%TutorClientAssignment{
      professional_id: nutritionist.id,
      client_id: client_user.id
    })

    %{
      conn: log_in_user(conn, nutritionist),
      nutritionist: nutritionist,
      client_user: client_user
    }
  end

  test "empty roster offers new client and import", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist/records")
    assert html =~ "No client records yet"
    assert html =~ "New client"
    assert html =~ "Import CSV"
  end

  test "existing records are listed", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, %{client: client}} =
      Importer.import_csv(nutritionist.id, File.read!(@fixture),
        user_id: client_user.id,
        full_name: "Maria K."
      )

    {:ok, _view, html} = live(conn, "/nutritionist/records")
    assert html =~ "Maria K."
    assert html =~ "/nutritionist/records/#{client.id}"
  end

  test "import flow: pick client → upload → preview → confirm creates a linked record", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/records/import")

    # A record can't be headless — pick the m3hungry client first.
    view
    |> element("form[phx-change='pick_client']")
    |> render_change(%{"user_id" => to_string(client_user.id)})

    upload =
      file_input(view, "#csv-import-form", :csv, [
        %{
          name: "history.csv",
          content: File.read!(@fixture),
          type: "text/csv"
        }
      ])

    render_upload(upload, "history.csv")

    html =
      view
      |> form("#csv-import-form")
      |> render_submit()

    assert html =~ "Preview import"
    assert html =~ "Platform Client"
    assert html =~ "15"

    render_click(view, "confirm_import")

    assert [record] = Professionals.list_client_records(nutritionist.id)
    assert record.user_id == client_user.id
    assert length(Professionals.list_consultation_notes(record.id)) == 15
  end

  test "confirm import without a selected client is refused", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/records/import")

    upload =
      file_input(view, "#csv-import-form", :csv, [
        %{name: "history.csv", content: File.read!(@fixture), type: "text/csv"}
      ])

    render_upload(upload, "history.csv")
    view |> form("#csv-import-form") |> render_submit()

    html = render_click(view, "confirm_import")

    assert html =~ "Select the m3hungry client"
    assert Professionals.list_client_records(nutritionist.id) == []
  end

  test "record show renders intake and notes timeline", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, %{client: client}} =
      Importer.import_csv(nutritionist.id, File.read!(@fixture),
        user_id: client_user.id,
        full_name: "Maria K."
      )

    {:ok, _view, html} = live(conn, "/nutritionist/records/#{client.id}")
    assert html =~ "Maria K."
    assert html =~ "Intake"
    assert html =~ "Consultation notes"
    assert html =~ "24-hour recall"
  end
end
