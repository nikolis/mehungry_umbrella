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

    view
    |> form("#onboarding-question-form",
      question: %{prompt_en: "Favorite cuisine?", question_type: "value", value_kind: "text"}
    )
    |> render_submit()

    assert [%{scope: "user", prompt_en: "Favorite cuisine?"}] = Onboarding.list_questions("user")
    assert render(view) =~ "Favorite cuisine?"
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
