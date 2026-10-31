defmodule MehungryWeb.NutritionistLive.OnboardingQuestionsTest do
  @moduledoc """
  Covers the nutritionist's client questionnaire editor (snapshot-on-first-use),
  the client self-fill form, and the user-onboarding answers surfaced back to the
  nutritionist on the client file.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.{Onboarding, Professionals, Repo, Subscriptions}
  alias Mehungry.Professionals.TutorClientAssignment

  setup %{conn: conn} do
    nutritionist = user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    client = user_fixture()

    Repo.insert!(%TutorClientAssignment{professional_id: nutritionist.id, client_id: client.id})

    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: nutritionist.id,
        user_id: client.id,
        full_name: "Test Client"
      })

    # An admin default the nutritionist's set is seeded from.
    {:ok, _} =
      Onboarding.create_question(%{
        "scope" => "client_default",
        "prompt_en" => "Reason for visit",
        "question_type" => "value"
      })

    %{nutritionist: nutritionist, client: client, record: record}
  end

  test "nutritionist editor seeds from the default on first open", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, _view, html} =
      conn |> log_in_user(nutritionist) |> live(~p"/nutritionist/onboarding-questions")

    assert html =~ "Client onboarding questions"
    assert html =~ "Reason for visit"
    assert [%{scope: "client"}] = Onboarding.list_questions("client", nutritionist.id)
  end

  test "client self-fills the questionnaire", %{
    conn: conn,
    nutritionist: nutritionist,
    client: client,
    record: record
  } do
    # Seed the nutritionist's own set.
    Onboarding.ensure_client_questions(nutritionist.id)
    [q] = Onboarding.list_active_questions("client", nutritionist.id)

    {:ok, view, html} =
      conn
      |> log_in_user(client)
      |> live(~p"/nutritionist-onboarding/#{nutritionist.id}")

    assert html =~ "Reason for visit"

    view
    |> form("form", %{"answers" => %{to_string(q.id) => %{"value_text" => "Weight management"}}})
    |> render_submit()

    answers = Onboarding.get_answers("professional_client", record.id)
    assert answers[q.id].value_text == "Weight management"
  end

  test "self-fill is refused to a non-client", %{conn: conn, nutritionist: nutritionist} do
    stranger = user_fixture()

    assert {:error, {:redirect, %{to: "/home"}}} =
             conn
             |> log_in_user(stranger)
             |> live(~p"/nutritionist-onboarding/#{nutritionist.id}")
  end

  test "user onboarding answers surface on the client file", %{
    conn: conn,
    nutritionist: nutritionist,
    client: client
  } do
    {:ok, uq} =
      Onboarding.create_question(%{
        "scope" => "user",
        "prompt_en" => "What is your main goal?",
        "question_type" => "value"
      })

    Onboarding.upsert_answers(
      "user",
      client.id,
      %{to_string(uq.id) => %{"value_text" => "Lower cholesterol"}},
      [uq]
    )

    {:ok, _view, html} =
      conn |> log_in_user(nutritionist) |> live(~p"/nutritionist/clients/#{client.id}")

    assert html =~ "Onboarding answers"
    assert html =~ "What is your main goal?"
    assert html =~ "Lower cholesterol"
  end
end
