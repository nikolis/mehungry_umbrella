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

  test "the summary strip survives a newest visit with no date", %{
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
        modality: "phone",
        body: "No date recorded for this visit"
      })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")
    assert html =~ "Last visit"
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
          body: "First online consult",
          hands_cm: "18.5",
          glutes_cm: "96.0",
          feet_cm: "24.5"
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
    assert note.hands_cm == 18.5
    assert note.glutes_cm == 96.0
    assert note.feet_cm == 24.5
  end

  test "'Edit details' lazily creates the record and saves the PII fields", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    view |> element("button", "Edit details") |> render_click()

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert record
    assert record.user_id == client_user.id

    html =
      view
      |> form("#client-details-form",
        client: %{full_name: "Edited Name", phone: "555-1234", date_of_birth: "1982-05-20"}
      )
      |> render_submit()

    assert html =~ "Client saved."

    updated = Professionals.get_client_record!(nutritionist.id, record.id)
    assert updated.full_name == "Edited Name"
    assert updated.phone == "555-1234"
    assert updated.date_of_birth == ~D[1982-05-20]
    # The required association is untouched by a details edit.
    assert updated.user_id == client_user.id
  end

  test "editing a visit updates its measurements and the page reflects them", %{
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

    {:ok, note} =
      Professionals.create_consultation_note(%{
        professional_client_id: record.id,
        visit_number: 1,
        visit_date: ~D[2026-02-01],
        modality: "phone",
        weight_kg: 90.0,
        body: "Original note"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    html = render_click(view, "edit_visit", %{"id" => to_string(note.id)})
    assert html =~ "Edit visit"

    html =
      view
      |> form("#new-visit-modal form",
        consultation_note: %{weight_kg: "88.5", body: "Corrected note", modality: "online"}
      )
      |> render_submit()

    assert html =~ "Visit updated."
    assert html =~ "Corrected note"
    refute html =~ "Original note"

    assert [saved] = Professionals.list_consultation_notes(record.id)
    assert saved.id == note.id
    assert saved.weight_kg == 88.5
    assert saved.modality == "online"
  end

  test "deleting a visit removes it and refreshes the page", %{
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

    {:ok, note} =
      Professionals.create_consultation_note(%{
        professional_client_id: record.id,
        visit_number: 1,
        visit_date: ~D[2026-02-01],
        body: "To be removed"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    html = render_click(view, "delete_visit", %{"id" => to_string(note.id)})

    assert html =~ "Visit deleted."
    refute html =~ "To be removed"
    assert Professionals.list_consultation_notes(record.id) == []
  end

  test "validate_intake recomputes BMI/BMR/TDEE on a source change, respects an override", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, _record} =
      Professionals.create_client_record(%{
        professional_id: nutritionist.id,
        user_id: client_user.id,
        full_name: "Platform Client"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")
    view |> element("button", "Add dietary history") |> render_click()

    sources = %{
      "height_m" => "1.70",
      "weight_kg" => "72",
      "sex" => "female",
      "age" => "34",
      "activity_level" => "moderate"
    }

    # A *source* edit → outputs recompute and show in the form.
    html =
      render_hook(view, "validate_intake", %{
        "_target" => ["intake", "weight_kg"],
        "intake" => sources
      })

    assert html =~ ~s(value="24.9")
    assert html =~ ~s(value="1452")
    assert html =~ ~s(value="#{round(1452 * 1.55)}")

    # An *output* edit (BMR typed) → the typed value is kept, not overwritten.
    html =
      render_hook(view, "validate_intake", %{
        "_target" => ["intake", "bmr_kcal"],
        "intake" => Map.put(sources, "bmr_kcal", "1600")
      })

    assert html =~ ~s(value="1600")
    refute html =~ ~s(value="1452")
  end

  test "assigns conditions from the record tab (lazy record), links to notes, and removes", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, ibs} = Mehungry.Health.create_condition(%{name: "IBS"})
    {:ok, gout} = Mehungry.Health.create_condition(%{name: "Gout"})

    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

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
    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=messages")

    html =
      view
      |> form("form[phx-submit='send_message']", %{body: "Hello from your nutritionist"})
      |> render_submit()

    assert html =~ "Hello from your nutritionist"
    assert [msg] = Professionals.list_messages(nutritionist.id, client_user.id)
    assert msg.sender_user_id == nutritionist.id
  end

  test "messages are marked read only when the Messages tab is opened", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, _} =
      Professionals.send_message(nutritionist.id, client_user.id, client_user.id, "Hi doc")

    assert Professionals.count_unread_messages_for(nutritionist.id) == 1

    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    # Landing on the Overview is NOT a read receipt — the unread badge shows in
    # the header (and on the Messages tab) instead.
    assert html =~ "1 unread message"
    assert Professionals.count_unread_messages_for(nutritionist.id) == 1

    # Opening the Messages tab is the receipt.
    html = render_patch(view, "/nutritionist/clients/#{client_user.id}?tab=messages")
    assert html =~ "Hi doc"
    assert Professionals.count_unread_messages_for(nutritionist.id) == 0
    refute html =~ "1 unread message"
  end

  test "an incoming message counts as unread until the Messages tab is open", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    # Sit on the Overview (the default tab).
    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    # Off the Messages tab: an incoming message lights the badge, unread stays.
    {:ok, _} =
      Professionals.send_message(nutritionist.id, client_user.id, client_user.id, "Ping")

    html = render(view)
    assert html =~ "1 unread message"
    assert Professionals.count_unread_messages_for(nutritionist.id) == 1

    # Opening the Messages tab clears the backlog…
    html = render_patch(view, "/nutritionist/clients/#{client_user.id}?tab=messages")
    assert html =~ "Ping"
    assert Professionals.count_unread_messages_for(nutritionist.id) == 0

    # …and while it stays open, a new message is read as it arrives.
    {:ok, _} =
      Professionals.send_message(nutritionist.id, client_user.id, client_user.id, "Ping 2")

    html = render(view)
    assert html =~ "Ping 2"
    refute html =~ "unread message"
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

  test "picking an appointment with a meeting link also prefills the online modality", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    appt =
      Repo.insert!(%Appointment{
        professional_id: nutritionist.id,
        client_id: client_user.id,
        scheduled_at: ~N[2026-04-22 10:00:00],
        title: "Online check-in",
        status: "accepted",
        meeting_url: "https://meet.google.com/abc-defg-hij"
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

    assert html =~ ~r/<option[^>]*selected[^>]*value="online"|<option[^>]*value="online"[^>]*selected/
  end

  test "a new visit is numbered after the highest existing number, not the count", %{
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

    # Visit 2 was deleted at some point: numbers on file are 1 and 3.
    for n <- [1, 3] do
      {:ok, _} =
        Professionals.create_consultation_note(%{
          professional_client_id: record.id,
          visit_number: n,
          visit_date: Date.add(~D[2026-01-05], n * 7),
          body: "Visit #{n}"
        })
    end

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    html = view |> element("button", "New visit") |> render_click()

    # count+1 would re-issue a duplicate "Visit 3"; max+1 gives 4.
    assert html =~ ~s(value="4")
  end

  test "the visit form shows the previous visit as reference with last-value hints", %{
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
      Professionals.create_consultation_note(%{
        professional_client_id: record.id,
        visit_number: 1,
        visit_date: ~D[2026-02-02],
        weight_kg: 82.4,
        waist_cm: 94.0,
        body: "Good week overall",
        todo: "Cut evening snacking"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    html = view |> element("button", "New visit") |> render_click()

    # The reference pane carries the previous measurements, note and to-do…
    assert html =~ "Last visit"
    assert html =~ "Good week overall"
    assert html =~ "Cut evening snacking"
    # …and the measurement inputs carry "last: X" hints.
    assert html =~ "last: 82.4 kg"
    assert html =~ "last: 94.0 cm"
  end

  test "the summary strip surfaces the last visit's to-do as Next steps", %{
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
      Professionals.create_consultation_note(%{
        professional_client_id: record.id,
        visit_number: 1,
        visit_date: ~D[2026-03-01],
        todo: "Bring blood work to the next session"
      })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Next steps"
    assert html =~ "Bring blood work to the next session"
  end

  test "setting the goal inline lazily creates the record and intake", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")
    assert html =~ "Set a goal"

    render_click(view, "edit_goal", %{})

    html =
      view
      |> form("form[phx-submit='save_goal']", %{goal: "Lose 6 kg by March"})
      |> render_submit()

    assert html =~ "Lose 6 kg by March"

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert record
    assert Professionals.get_latest_intake(record.id).goal == "Lose 6 kg by March"
  end

  test "editing the goal inline updates the existing intake", %{
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

    {:ok, intake} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "goal" => "Old goal",
        "weight_kg" => 90.0
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    render_click(view, "edit_goal", %{})

    html =
      view
      |> form("form[phx-submit='save_goal']", %{goal: "Maintain 78 kg"})
      |> render_submit()

    assert html =~ "Maintain 78 kg"

    updated = Professionals.get_latest_intake(record.id)
    assert updated.id == intake.id
    assert updated.goal == "Maintain 78 kg"
    # The rest of the intake is untouched.
    assert updated.weight_kg == 90.0
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

    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=planning")

    assert html =~ "Assign a saved plan"
    assert html =~ "UC Weekly — Week 1"

    # A non-past start date — assign_plan now rejects past weeks, matching the
    # calendar's own guard.
    start = Date.add(Date.utc_today(), 7)
    week_end = Date.add(start, 6)

    html =
      view
      |> form("form[phx-submit='assign_plan']",
        assign: %{plan_id: "#{plan.id}", start_date: Date.to_iso8601(start)}
      )
      |> render_submit()

    assert html =~ "Added 1 meals to"

    # The meal landed on the *client's* calendar, not the nutritionist's.
    assert [_meal] = History.list_user_meals_in_range(client_user.id, start, week_end)

    assert [] = History.list_user_meals_in_range(nutritionist.id, start, week_end)
  end

  test "assigning a plan to a past week is rejected", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, bp} =
      MealBlueprints.create_blueprint(
        MealBlueprints.default_blueprint_attrs(nutritionist.id, "Past Weekly")
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

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=planning")

    past = Date.add(Date.utc_today(), -7)

    html =
      view
      |> form("form[phx-submit='assign_plan']",
        assign: %{plan_id: "#{plan.id}", start_date: Date.to_iso8601(past)}
      )
      |> render_submit()

    assert html =~ "can&#39;t be in the past"
    assert [] = History.list_user_meals_in_range(client_user.id, past, Date.add(past, 6))
  end

  test "assign-plan panel points to the blueprint builder when there are no plans", %{
    conn: conn,
    client_user: client_user
  } do
    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=planning")

    assert html =~ "Assign a saved plan"
    assert html =~ "You have no completed plans yet"
  end

  test "existing intake dietary history is shown on the record tab", %{
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
          "allergies" => "στην υγρασία",
          "sleep" => "καλός, ξεκούραστος",
          "recall_24h" => %{"breakfast" => "brunch: 12:00 ομελέτα"}
        }
      })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

    assert html =~ "Dietary History"
    assert html =~ "Reason for visit"
    assert html =~ "χάσιμο βάρους"
    assert html =~ "89 κιλά για αρχή"
    assert html =~ "24-hour recall"
    assert html =~ "brunch: 12:00 ομελέτα"

    # Lifecycle grouping: allergy renders as an always-visible flag chip, the
    # rest inside their collapsible sections (content still in the DOM).
    assert html =~ "στην υγρασία"
    assert html =~ "Lifestyle &amp; eating habits"
    assert html =~ "Story &amp; goals"
    assert html =~ "καλός, ξεκούραστος"
    refute html =~ "Medical background"
  end

  test "progress chart renders once there are >= 2 dated weights", %{
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

    assert html =~ "Progress trend"
    # The progress dashboard: KPI cards (drive the chart) + a server-rendered SVG trend.
    assert html =~ ~s(phx-click="select_metric")
    assert html =~ "<svg"
    refute html =~ "Not enough data yet"
  end

  test "progress chart shows the empty state with fewer than 2 readings", %{
    conn: conn,
    client_user: client_user
  } do
    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Progress trend"
    assert html =~ "Not enough data yet"
    refute html =~ ~s(phx-click="select_metric")
  end

  test "a new visit persists the body-composition measurements", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    view |> element("button", "New visit") |> render_click()

    view
    |> form("#new-visit-modal form",
      consultation_note: %{
        visit_number: "1",
        visit_date: "2026-02-01",
        modality: "in_person",
        weight_kg: "88.0",
        body_fat_percentage: "27.5",
        waist_cm: "82.0",
        muscle_mass_kg: "31.0"
      }
    )
    |> render_submit()

    record = Professionals.get_client_record_by_user(nutritionist.id, client_user.id)
    assert [note] = Professionals.list_consultation_notes(record.id)
    assert note.weight_kg == 88.0
    assert note.body_fat_percentage == 27.5
    assert note.waist_cm == 82.0
    assert note.muscle_mass_kg == 31.0
  end

  test "the progress chart offers a metric selector across available metrics", %{
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

    for {date, bf} <- [{~D[2026-01-10], 30.0}, {~D[2026-02-10], 28.0}] do
      {:ok, _} =
        Professionals.create_consultation_note(%{
          professional_client_id: record.id,
          visit_date: date,
          weight_kg: 88.0,
          body_fat_percentage: bf
        })
    end

    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    # Both weight and body fat have >= 2 points, so both appear in the selector.
    assert html =~ "Weight"
    assert html =~ "Body fat"

    # Switching metric rebuilds the chart without error.
    html = render_click(view, "select_metric", %{"metric" => "body_fat_percentage"})
    assert html =~ "<svg"
    assert html =~ "Body fat (%)"
  end

  test "adding dietary history inline lazily creates the record and intake", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    assert Professionals.get_client_record_by_user(nutritionist.id, client_user.id) == nil

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

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

  # ── Phase 2: tabbed IA, session ribbon, plan preview, onboarding-beside-intake ──

  test "the client file opens on Overview and the tab bar switches sections", %{
    conn: conn,
    client_user: client_user
  } do
    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    # Default tab is Overview: the summary strip is there, the clinical record
    # and planning panels are not.
    assert html =~ "Progress trend"
    refute html =~ "Dietary History"
    refute html =~ "Assign a saved plan"

    # Record tab reveals the clinical file.
    html = render_patch(view, "/nutritionist/clients/#{client_user.id}?tab=record")
    assert html =~ "Dietary History"
    refute html =~ "Assign a saved plan"

    # Planning tab reveals the plan/AI tools.
    html = render_patch(view, "/nutritionist/clients/#{client_user.id}?tab=planning")
    assert html =~ "Assign a saved plan"
    assert html =~ "AI Meal Plan Assistant"
  end

  test "an unknown tab falls back to Overview", %{conn: conn, client_user: client_user} do
    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=bogus")
    assert html =~ "Progress trend"
  end

  test "the session ribbon highlights an imminent appointment with a Log visit action", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    soon =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.add(2 * 3600, :second)

    Repo.insert!(%Appointment{
      professional_id: nutritionist.id,
      client_id: client_user.id,
      scheduled_at: soon,
      title: "Follow-up consult",
      status: "accepted"
    })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    assert html =~ "Follow-up consult"
    assert html =~ "Log visit"
  end

  test "no session ribbon when the next appointment is beyond the window", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    far =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.add(10 * 24 * 3600, :second)

    Repo.insert!(%Appointment{
      professional_id: nutritionist.id,
      client_id: client_user.id,
      scheduled_at: far,
      title: "Distant consult",
      status: "accepted"
    })

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}")

    # No ribbon (its "Log visit" button is absent); the appointment still shows
    # in the appointment-history list, which is expected.
    refute html =~ "Log visit"
  end

  test "selecting a plan previews its meals before assigning", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, bp} =
      MealBlueprints.create_blueprint(
        MealBlueprints.default_blueprint_attrs(nutritionist.id, "Preview Weekly")
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

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=planning")

    # Choosing the plan (a form change) renders the 7-day digest before any
    # destructive assign.
    html =
      view
      |> form("#assign-plan-form")
      |> render_change(%{"assign" => %{"plan_id" => "#{plan.id}", "start_date" => Date.to_iso8601(Date.utc_today())}})

    assert html =~ "This plan lays down"
    assert html =~ "Day 1"
    assert html =~ recipe.title
  end

  test "onboarding answers sit beside the intake form while editing", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, question} =
      Mehungry.Onboarding.create_question(%{
        scope: "user",
        prompt_en: "What brings you here?",
        question_type: "value",
        value_kind: "text"
      })

    {:ok, _} =
      Mehungry.Onboarding.upsert_answers(
        "user",
        client_user.id,
        %{to_string(question.id) => %{"value_text" => "I keep regaining weight"}},
        [question]
      )

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

    html = view |> element("button", "Add dietary history") |> render_click()

    # The form and the client's own words render together, with a copy affordance.
    assert html =~ "Client&#39;s onboarding answers"
    assert html =~ "What brings you here?"
    assert html =~ "I keep regaining weight"
    assert html =~ ~s(phx-hook="Copy")
  end

  # ── Phase 3: re-assessment, printable record, AI resume ──────────────────────

  test "a new assessment creates a second intake prefilled from the latest", %{
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
        "assessed_on" => "2026-01-10",
        "goal" => "Baseline goal",
        "weight_kg" => 90.0
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

    # "New assessment" opens the form prefilled from the latest.
    html = view |> element("button", "New assessment") |> render_click()
    assert html =~ ~s(value="Baseline goal")
    assert html =~ ~s(value="90.0")

    # Saving (with an adjusted goal) creates a SECOND assessment; the first is kept.
    view
    |> form("#intake-form", intake: %{goal: "Updated goal", weight_kg: "88"})
    |> render_submit()

    intakes = Professionals.list_intakes(record.id)
    assert length(intakes) == 2
    assert Enum.map(intakes, & &1.goal) |> Enum.sort() == ["Baseline goal", "Updated goal"]
  end

  test "past assessments are viewable read-only via the history switcher", %{
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

    {:ok, old} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-01-10",
        "goal" => "Old goal"
      })

    {:ok, _new} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-06-10",
        "goal" => "New goal"
      })

    {:ok, view, html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

    # Both assessment dates are offered; the latest shows by default.
    assert html =~ "Jan 10, 2026"
    assert html =~ "Jun 10, 2026"
    assert html =~ "New goal"

    # Switching to the older one shows it read-only.
    html = render_click(view, "select_assessment", %{"id" => to_string(old.id)})
    assert html =~ "Old goal"
    assert html =~ "Viewing a past assessment"
  end

  test "the AI assistant resumes its running state after a re-mount", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    # A draft is already in flight (Oban is in :manual test mode, so the job
    # stays queued).
    {:ok, _job} =
      Mehungry.ObanWorkers.NutritionistAgentWorker.enqueue(
        nutritionist.id,
        client_user.id,
        "Platform Client",
        "low-carb"
      )

    {:ok, _view, html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=planning")

    assert html =~ "Drafting in progress"
  end

  test "editing the goal after browsing an older assessment writes to the latest, not the browsed row", %{
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

    {:ok, old} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-01-10",
        "goal" => "Old goal"
      })

    {:ok, latest} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-06-10",
        "goal" => "Latest goal"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

    # Browse the older assessment (points the Record-tab focus at it), then edit
    # the goal from the Overview strip.
    render_click(view, "select_assessment", %{"id" => to_string(old.id)})
    render_patch(view, "/nutritionist/clients/#{client_user.id}?tab=overview")
    render_click(view, "edit_goal", %{})

    view
    |> form("form[phx-submit='save_goal']", %{goal: "Edited goal"})
    |> render_submit()

    # The LATEST got the edit; the browsed historical row is untouched.
    assert Professionals.get_latest_intake(record.id).goal == "Edited goal"
    assert Mehungry.Repo.reload(old).goal == "Old goal"
  end

  test "a new assessment prefills from the latest even after browsing an older one", %{
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

    {:ok, old} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-01-10",
        "goal" => "Old goal"
      })

    {:ok, _latest} =
      Professionals.create_intake(%{
        "professional_client_id" => record.id,
        "assessed_on" => "2026-06-10",
        "goal" => "Latest goal"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client_user.id}?tab=record")

    render_click(view, "select_assessment", %{"id" => to_string(old.id)})
    html = render_click(view, "new_assessment", %{})

    # Seeded from the latest, not the browsed historical row.
    assert html =~ ~s(value="Latest goal")
    refute html =~ ~s(value="Old goal")
  end

  test "the disconnected render does not fire the read receipt", %{
    conn: conn,
    nutritionist: nutritionist,
    client_user: client_user
  } do
    {:ok, _} =
      Professionals.send_message(nutritionist.id, client_user.id, client_user.id, "Hi doc")

    assert Professionals.count_unread_messages_for(nutritionist.id) == 1

    # A plain GET renders the LiveView disconnected (no live socket) — this must
    # NOT mark the thread read, even on the Messages tab.
    conn = get(conn, "/nutritionist/clients/#{client_user.id}?tab=messages")
    assert html_response(conn, 200) =~ "Hi doc"
    assert Professionals.count_unread_messages_for(nutritionist.id) == 1
  end

  test "the record page offers a print action", %{
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

    {:ok, _view, html} = live(conn, "/nutritionist/records/#{record.id}")

    assert html =~ "Print / Save as PDF"
    assert html =~ "window.print()"
    assert html =~ "@media print"
  end
end
