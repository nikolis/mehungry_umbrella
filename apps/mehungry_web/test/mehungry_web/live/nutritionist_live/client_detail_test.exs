defmodule MehungryWeb.NutritionistLive.ClientDetailTest do
  @moduledoc """
  Smoke tests for the client "User Overview": showing the client's dietary-history
  visits as an accordion and recording a new visit.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.{History, MealBlueprints, Professionals, Repo, Subscriptions}
  alias Mehungry.Professionals.{Appointment, TutorClientAssignment}

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

  test "'Open full record' lazily creates the record and navigates to its editor", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    result = view |> element("button", "Open full record") |> render_click()

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert record
    assert record.user_id == client_user.id

    assert {:error, {:live_redirect, %{to: path}}} = result
    assert path == "/nutritionist/records/#{record.id}/edit"
  end

  test "assigns conditions from the overview (lazy record), links to notes, and removes", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, ibs} = Mehungry.Health.create_condition(%{name: "IBS"})
    {:ok, gout} = Mehungry.Health.create_condition(%{name: "Gout"})

    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    # Adding the first condition lazily creates the client record.
    view
    |> form("form[phx-submit='add_condition']", %{condition_id: ibs.id})
    |> render_submit()

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert record
    assert [%{name: "IBS"}] = Professionals.list_client_conditions(record.id)

    html =
      view
      |> form("form[phx-submit='add_condition']", %{condition_id: gout.id})
      |> render_submit()

    # Both are listed, each offering a notes link scoped to that condition.
    assert html =~ "IBS"
    assert html =~ "Gout"
    assert html =~ "/nutritionist/research/notes?condition_id=#{ibs.id}"
    assert html =~ "/nutritionist/research/notes?condition_id=#{gout.id}"

    # Remove one (browser sends the id as a string).
    render_click(view, "remove_condition", %{"id" => to_string(ibs.id)})
    assert [%{name: "Gout"}] = Professionals.list_client_conditions(record.id)
  end

  test "nutritionist sends a message and it appears in the thread", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    html =
      view
      |> form("form[phx-submit='send_message']", %{body: "Hello from your nutritionist"})
      |> render_submit()

    assert html =~ "Hello from your nutritionist"
    assert [msg] = Professionals.list_messages(nutritionist.id, client_user.id)
    assert msg.sender_user_id == nutritionist.id
  end

  test "a client's message is marked read when the nutritionist opens the client", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, _} =
      Professionals.send_message(nutritionist.id, client_user.id, client_user.id, "Hi doc")

    assert Professionals.count_unread_messages_for(nutritionist.id) == 1

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Hi doc"
    assert Professionals.count_unread_messages_for(nutritionist.id) == 0
  end

  test "a visit can be stamped to an appointment, cross-referenced both ways", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    appt =
      Repo.insert!(%Appointment{
        professional_id: nutritionist.id,
        client_id: client_user.id,
        scheduled_at: ~N[2026-03-10 09:00:00],
        title: "Follow-up consult",
        status: "accepted"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    view |> element("button", "New visit") |> render_click()

    html =
      view
      |> form("#new-visit-modal form",
        consultation_note: %{
          visit_number: "2",
          visit_date: "2026-03-10",
          modality: "in_person",
          appointment_id: "#{appt.id}",
          body: "Reviewed progress"
        }
      )
      |> render_submit()

    # Visit shows its linked appointment …
    assert html =~ "Reviewed progress"
    assert html =~ "Linked appointment"
    assert html =~ "Follow-up consult"
    # … and the appointment history is badged in reverse.
    assert html =~ "Visit note recorded"

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert [note] = Professionals.list_consultation_notes(record.id)
    assert note.appointment_id == appt.id
  end

  test "picking an appointment in the visit form prefills the visit date", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    appt =
      Repo.insert!(%Appointment{
        professional_id: nutritionist.id,
        client_id: client_user.id,
        scheduled_at: ~N[2026-04-20 14:30:00],
        title: "Initial consult",
        status: "accepted"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    view |> element("button", "New visit") |> render_click()

    html =
      view
      |> form("#new-visit-modal form")
      |> render_change(%{
        "_target" => ["consultation_note", "appointment_id"],
        "consultation_note" => %{"appointment_id" => "#{appt.id}"}
      })

    assert html =~ ~s(value="2026-04-20")
  end

  test "a saved plan can be assigned straight to this client's calendar", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, bp} =
      MealBlueprints.create_blueprint(
        MealBlueprints.default_blueprint_attrs(nutritionist.id, "UC Weekly")
      )

    {:ok, plan} =
      MealBlueprints.create_plan(%{
        name: "Week 1",
        start_date: Date.utc_today(),
        status: "generating",
        blueprint_id: bp.id,
        user_id: nutritionist.id
      })

    recipe = recipe_fixture(nutritionist)

    # store_plan_meals marks the plan "completed" → it becomes assignable.
    {:ok, _plan} =
      MealBlueprints.store_plan_meals(plan, [
        %{
          day_index: 1,
          meal_type: "breakfast",
          recipe_id: recipe.id,
          cooking_portions: 2,
          ingredient_id: nil,
          quantity: nil,
          measurement_unit_id: nil,
          ingredient_portion_id: nil
        }
      ])

    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Assign a saved plan"
    assert html =~ "UC Weekly — Week 1"

    html =
      view
      |> form("form[phx-submit='assign_plan']",
        assign: %{plan_id: "#{plan.id}", start_date: "2026-05-04"}
      )
      |> render_submit()

    assert html =~ "Added 1 meals to"

    # The meal landed on the *client's* calendar, not the nutritionist's.
    assert [_meal] =
             History.list_user_meals_in_range(client_user.id, ~D[2026-05-04], ~D[2026-05-10])

    assert [] = History.list_user_meals_in_range(nutritionist.id, ~D[2026-05-04], ~D[2026-05-10])
  end

  test "assign-plan panel points to the blueprint builder when there are no plans", %{
    conn: conn,
    client_user: client_user
  } do
    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Assign a saved plan"
    assert html =~ "You have no completed plans yet"
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

  test "weight trend chart renders once there are >= 2 dated weights", %{
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

    {:ok, _} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-01-10",
        "weight_kg" => 90.0
      })

    {:ok, _} =
      Professionals.create_consultation_note(%{
        professional_client_id: record.id,
        visit_date: ~D[2026-02-05],
        weight_kg: 88.5
      })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Weight trend"
    # The Vega-Lite chart hook is mounted with the encoded spec.
    assert html =~ ~s(id="vega-weight")
    assert html =~ ~s(phx-hook="VegaLite")
    refute html =~ "Not enough weight data yet"
  end

  test "weight trend shows the empty state with fewer than 2 weights", %{
    conn: conn,
    client_user: client_user
  } do
    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Weight trend"
    assert html =~ "Not enough weight data yet"
    refute html =~ ~s(id="vega-weight")
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
