defmodule MehungryWeb.NutritionistLive.ClientDetailTest do
  @moduledoc """
  Smoke tests for the client "User Overview": showing the client's dietary-history
  visits as an accordion and recording a new visit.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo, Subscriptions}
  alias Mehungry.Professionals.TutorClientAssignment

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

  test "existing visits are shown with basic info in the overview", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: nutritionist.id,
        user_id: client_user.id,
        full_name: "Platform Client"
      })

    {:ok, _note} =
      Professionals.create_consultation_note(%{
        professional_client_id: record.id,
        visit_number: 1,
        visit_date: ~D[2026-01-15],
        modality: "phone",
        body: "Detailed private notes here"
      })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Client Record — Visits"
    assert html =~ "Visit 1"
    assert html =~ "Phone"
    # Full notes are present in the DOM (hidden until expand).
    assert html =~ "Detailed private notes here"
  end

  test "recording a new visit lazily creates a client record and the note", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    view |> element("button", "New visit") |> render_click()

    html =
      view
      |> form("#new-visit-modal form",
        consultation_note: %{
          visit_number: "1",
          visit_date: "2026-02-01",
          modality: "online",
          body: "First online consult"
        }
      )
      |> render_submit()

    assert html =~ "Visit recorded."
    assert html =~ "First online consult"

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert record
    assert [note] = Professionals.list_consultation_notes(record.id)
    assert note.body == "First online consult"
    assert note.modality == "online"
  end

  test "existing intake dietary history is shown in the overview", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: nutritionist.id,
        user_id: client_user.id,
        full_name: "Platform Client"
      })

    {:ok, _intake} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "goal" => "89 κιλά για αρχή",
        "weight_kg" => 90.0,
        "details" => %{
          "reason_for_visit" => "χάσιμο βάρους",
          "marital_status" => "ελεύθερη",
          "recall_24h" => %{"breakfast" => "brunch: 12:00 ομελέτα"}
        }
      })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Dietary History"
    assert html =~ "Reason for visit"
    assert html =~ "χάσιμο βάρους"
    assert html =~ "89 κιλά για αρχή"
    assert html =~ "24-hour recall"
    assert html =~ "brunch: 12:00 ομελέτα"
  end

  test "adding dietary history inline lazily creates the record and intake", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    view |> element("button", "Add dietary history") |> render_click()

    html =
      view
      |> form("#intake-form",
        intake: %{
          goal: "χάσιμο βάρους",
          details: %{
            reason_for_visit: "νέο ξεκίνημα",
            recall_24h: %{breakfast: "ομελέτα με λαχανικά"}
          }
        }
      )
      |> render_submit()

    assert html =~ "Dietary history saved."
    assert html =~ "νέο ξεκίνημα"

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert record
    intake = Professionals.get_latest_intake(record.id)
    assert intake.goal == "χάσιμο βάρους"
    assert intake.details["reason_for_visit"] == "νέο ξεκίνημα"
    assert intake.details["recall_24h"]["breakfast"] == "ομελέτα με λαχανικά"
  end
end
