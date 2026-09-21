defmodule MehungryWeb.NutritionistLive.ClientRecordEditorTest do
  @moduledoc """
  Smoke tests for the manual client-record authoring UI: creating a client
  linked to a required m3hungry platform user, filling the typed + questionnaire
  + 24h-recall intake and a consultation note (and seeing them on the read-only
  record page), the linked-user requirement, a failed email lookup, and the
  ownership redirect.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo, Subscriptions}
  alias Mehungry.Professionals.TutorClientAssignment

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _} =
      Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    %{conn: log_in_user(conn, nutritionist), user: nutritionist}
  end

  test "creates a client linked to an m3hungry user, fills intake + a note, read-only page renders them",
       %{conn: conn, user: user} do
    client_user = Mehungry.AccountsFixtures.user_fixture()
    client_user = Repo.update!(Ecto.Changeset.change(client_user, name: "John Client"))
    Repo.insert!(%TutorClientAssignment{professional_id: user.id, client_id: client_user.id})

    {:ok, view, _html} = live(conn, "/nutritionist/records/new")

    view
    |> element("form[phx-change='pick_assigned']")
    |> render_change(%{"user_id" => to_string(client_user.id)})

    result =
      view
      |> form("form[phx-submit='save_client']", client: %{full_name: "John Client"})
      |> render_submit()

    {:ok, edit_view, _html} = follow_redirect(result, conn)

    [record] = Professionals.list_client_records(user.id)
    assert record.full_name == "John Client"
    assert record.user_id == client_user.id

    # Intake: a typed field, a questionnaire detail key, and a recall key.
    edit_view
    |> form("form[phx-submit='save_intake']",
      intake: %{
        height_m: "1.75",
        weight_kg: "80",
        details: %{
          "reason_for_visit" => "Weight loss",
          "recall_24h" => %{"breakfast" => "Oats"}
        }
      }
    )
    |> render_submit()

    intake = Professionals.get_latest_intake(record.id)
    assert intake.height_m == 1.75
    assert intake.weight_kg == 80.0
    assert intake.details["reason_for_visit"] == "Weight loss"
    assert intake.details["recall_24h"]["breakfast"] == "Oats"

    # Add a consultation note, then fill it.
    render_click(edit_view, "add_note")
    [note] = Professionals.list_consultation_notes(record.id)

    edit_view
    |> form("form[phx-submit='save_note']",
      note: %{_id: note.id, visit_number: "1", modality: "phone", body: "First visit."}
    )
    |> render_submit()

    saved = Professionals.list_consultation_notes(record.id) |> hd()
    assert saved.body == "First visit."
    assert saved.modality == "phone"

    # Read-only record page shows all of it.
    {:ok, _v, html} = live(conn, "/nutritionist/records/#{record.id}")
    assert html =~ "Weight loss"
    assert html =~ "Oats"
    assert html =~ "First visit."
    assert html =~ "John Client"
  end

  test "links an m3hungry platform client from the assigned-clients dropdown",
       %{conn: conn, user: user} do
    client_user = Mehungry.AccountsFixtures.user_fixture()
    client_user = Repo.update!(Ecto.Changeset.change(client_user, name: "Platform Client"))

    Repo.insert!(%TutorClientAssignment{professional_id: user.id, client_id: client_user.id})

    {:ok, view, _html} = live(conn, "/nutritionist/records/new")

    view
    |> element("form[phx-change='pick_assigned']")
    |> render_change(%{"user_id" => to_string(client_user.id)})

    result = view |> form("form[phx-submit='save_client']") |> render_submit()
    {:ok, _edit_view, _html} = follow_redirect(result, conn)

    [record] = Professionals.list_client_records(user.id)
    assert record.user_id == client_user.id
    assert record.full_name == "Platform Client"
  end

  test "saving without a linked m3hungry user is refused", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/nutritionist/records/new")

    html =
      view
      |> form("form[phx-submit='save_client']", client: %{full_name: "No Account"})
      |> render_submit()

    assert html =~ "records can&#39;t be headless" or html =~ "records can't be headless"
    assert Professionals.list_client_records(user.id) == []
  end

  test "an email lookup with no matching account flashes an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/nutritionist/records/new")

    html =
      view
      |> form("form[phx-submit='lookup_email']", %{email: "nobody@example.com"})
      |> render_submit()

    assert html =~ "No m3hungry account found"
  end

  test "editing another professional's record redirects away", %{conn: conn} do
    other = Mehungry.AccountsFixtures.user_fixture()

    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: other.id,
        user_id: other.id,
        full_name: "Not Yours"
      })

    assert {:error, {:live_redirect, %{to: "/nutritionist/records"}}} =
             live(conn, "/nutritionist/records/#{record.id}/edit")
  end
end
