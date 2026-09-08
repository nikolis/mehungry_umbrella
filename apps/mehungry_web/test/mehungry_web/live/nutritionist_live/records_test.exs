defmodule MehungryWeb.NutritionistLive.RecordsTest do
  @moduledoc """
  Smoke tests for the client-records roster and the dietary-history CSV import
  flow (upload → preview → confirm).
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Subscriptions}
  alias Mehungry.Professionals.DietaryHistory.Importer

  @fixture Path.expand(
             "../../../../../mehungry/test/fixtures/dietary_history_sample.csv",
             __DIR__
           )

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _} =
      Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    %{conn: log_in_user(conn, nutritionist), nutritionist: nutritionist}
  end

  test "empty roster invites the first import", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist/records")
    assert html =~ "No client records yet"
    assert html =~ "Import a dietary-history sheet"
  end

  test "existing records are listed", %{conn: conn, nutritionist: nutritionist} do
    {:ok, %{client: client}} =
      Importer.import_csv(nutritionist.id, File.read!(@fixture), full_name: "Maria K.")

    {:ok, _view, html} = live(conn, "/nutritionist/records")
    assert html =~ "Maria K."
    assert html =~ "/nutritionist/records/#{client.id}"
  end

  test "import flow: upload → preview → confirm creates a record", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/records/import")

    upload =
      file_input(view, "form", :csv, [
        %{
          name: "history.csv",
          content: File.read!(@fixture),
          type: "text/csv"
        }
      ])

    render_upload(upload, "history.csv")

    html =
      view
      |> form("form", %{"name" => "Maria K."})
      |> render_submit()

    assert html =~ "Preview import"
    assert html =~ "Maria K."
    assert html =~ "15"

    render_click(view, "confirm_import")

    assert [record] = Professionals.list_client_records(nutritionist.id)
    assert record.full_name == "Maria K."
    assert length(Professionals.list_consultation_notes(record.id)) == 15
  end

  test "record show renders intake and notes timeline", %{conn: conn, nutritionist: nutritionist} do
    {:ok, %{client: client}} =
      Importer.import_csv(nutritionist.id, File.read!(@fixture), full_name: "Maria K.")

    {:ok, _view, html} = live(conn, "/nutritionist/records/#{client.id}")
    assert html =~ "Maria K."
    assert html =~ "Intake"
    assert html =~ "Consultation notes"
    assert html =~ "24-hour recall"
  end
end
