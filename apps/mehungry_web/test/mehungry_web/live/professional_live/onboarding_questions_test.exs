defmodule MehungryWeb.ProfessionalLive.OnboardingQuestionsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Onboarding

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin)}
  end

  test "creates a user-scope value question", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/onboarding-questions/user")

    assert render(view) =~ "User onboarding questions"

    view |> element("button", "Add question") |> render_click()

    # The form presents one "answer shape" radio; "short_text" expands to the
    # stored question_type: "value" / value_kind: "text" pair.
    view
    |> form("#onboarding-question-form",
      question: %{prompt_en: "Favorite cuisine?", answer_shape: "short_text"}
    )
    |> render_submit()

    assert [%{scope: "user", prompt_en: "Favorite cuisine?", question_type: "value", value_kind: "text"}] =
             Onboarding.list_questions("user")

    assert render(view) =~ "Favorite cuisine?"
  end

  test "creates a single-choice question with options", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/onboarding-questions/user")

    view |> element("button", "Add question") |> render_click()

    # Choosing "Pick one" reveals the answer-options editor (absent before).
    html =
      view
      |> form("#onboarding-question-form", question: %{answer_shape: "single_choice"})
      |> render_change()

    assert html =~ "Answer options"

    # Add a choice row, then fill it in and save.
    view
    |> form("#onboarding-question-form", question: %{answer_shape: "single_choice"})
    |> render_submit(%{"question" => %{"_action" => "add_option"}})

    view
    |> form("#onboarding-question-form",
      question: %{
        prompt_en: "Reason for visit?",
        answer_shape: "single_choice",
        options: %{"0" => %{label_en: "First visit"}}
      }
    )
    |> render_submit()

    assert [%{prompt_en: "Reason for visit?", question_type: "single_choice", options: [opt]}] =
             Onboarding.list_questions("user")

    assert opt.label_en == "First visit"
    assert render(view) =~ "Reason for visit?"
  end

  test "edits the client-default scope independently", %{conn: conn} do
    {:ok, _q} =
      Onboarding.create_question(%{
        "scope" => "client_default",
        "prompt_en" => "Reason for visit",
        "question_type" => "value"
      })

    {:ok, view, html} = live(conn, ~p"/professional/onboarding-questions/client-default")

    assert html =~ "Nutritionist client questionnaire"
    assert html =~ "Reason for visit"
    # The user scope is untouched by seeding the client default.
    assert Onboarding.list_questions("user") == []
    refute render(view) =~ "Favorite cuisine?"
  end
end
