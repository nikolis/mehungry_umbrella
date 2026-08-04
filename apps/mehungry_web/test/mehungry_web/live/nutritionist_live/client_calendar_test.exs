defmodule MehungryWeb.NutritionistLive.ClientCalendarTest do
  @moduledoc """
  Regression tests for the nutritionist client meal-planning calendar.

  These guard the create/edit-meal flow that was previously missing: the
  calendar's "Add Meal" button and per-meal edit buttons fire events that
  `push_patch` to `/nutritionist/clients/:id/calendar/:date/:title` and
  `/nutritionist/clients/:id/calendar/edit/:meal_id`. If those routes,
  `apply_action` clauses, or the modal are dropped again, these tests fail.
  """
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest

  alias Mehungry.History
  alias Mehungry.Professionals.TutorClientAssignment
  alias Mehungry.Repo
  alias Mehungry.Subscriptions

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()

    # The :nutritionist live_session requires a "pro" subscription tier.
    {:ok, _} =
      Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    {:ok, _assignment} =
      %TutorClientAssignment{}
      |> TutorClientAssignment.changeset(%{
        professional_id: nutritionist.id,
        client_id: client.id
      })
      |> Repo.insert()

    # The calendar widget only renders (instead of a loading spinner) once it
    # knows the viewport width, which is read from the LiveView connect params.
    conn =
      conn
      |> log_in_user(nutritionist)
      |> Phoenix.LiveViewTest.put_connect_params(%{"viewport" => %{"width" => 1280}})

    %{conn: conn, nutritionist: nutritionist, client: client}
  end

  defp client_meal(client) do
    recipe = recipe_fixture(client)

    {:ok, meal} =
      History.create_user_meal(%{
        start_dt: NaiveDateTime.utc_now(),
        end_dt: NaiveDateTime.utc_now(),
        user_id: client.id,
        title: "Client lunch",
        recipe_user_meals: [
          %{recipe_id: recipe.id, consume_portions: 1, cooking: true, cooking_portions: 1}
        ]
      })

    meal
  end

  describe "meal creation flow" do
    test "the calendar index renders and the Add Meal button is present", %{
      conn: conn,
      client: client
    } do
      {:ok, view, html} = live(conn, "/nutritionist/clients/#{client.id}/calendar")
      assert html =~ "meal plan"
      assert has_element?(view, "#button_calendar")
    end

    test "clicking Add Meal opens the meal form modal (does not crash)", %{
      conn: conn,
      client: client
    } do
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}/calendar")

      view
      |> element("#button_calendar")
      |> render_click()

      # The click fans out pick-date -> {:initial_modal, ...} -> push_patch(:new).
      # It must land on a real route (this used to raise on a missing one)...
      path = assert_patch(view)
      assert path =~ ~r{^/nutritionist/clients/#{client.id}/calendar/.+}

      # ...and the modal only renders for the :new/:edit live actions, so its
      # presence proves the whole create-meal chain resolved.
      assert has_element?(view, "#client_calendar_modal")
    end

    test "navigating directly to the :new route renders the modal", %{
      conn: conn,
      client: client
    } do
      today = Date.utc_today() |> Date.to_iso8601()

      {:ok, view, _html} =
        live(conn, "/nutritionist/clients/#{client.id}/calendar/#{today}/breakfast")

      assert has_element?(view, "#client_calendar_modal")
    end
  end

  describe "meal editing flow" do
    test "the edit route renders the modal for a meal owned by the client", %{
      conn: conn,
      client: client
    } do
      meal = client_meal(client)

      {:ok, view, _html} =
        live(conn, "/nutritionist/clients/#{client.id}/calendar/edit/#{meal.id}")

      assert has_element?(view, "#client_calendar_modal")
    end

    test "a nutritionist cannot edit a meal that does not belong to their client", %{
      conn: conn,
      client: client
    } do
      other_user = Mehungry.AccountsFixtures.user_fixture()
      foreign_meal = client_meal(other_user)

      # The guard patches back to the plain calendar with a flash, which
      # LiveViewTest surfaces as a live_redirect — the modal is never shown.
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, "/nutritionist/clients/#{client.id}/calendar/edit/#{foreign_meal.id}")

      assert to == "/nutritionist/clients/#{client.id}/calendar"
      assert flash["error"] =~ "Not authorized"
    end
  end
end
