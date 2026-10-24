defmodule MehungryWeb.Api.V1.FeedbackTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Feedback

  describe "POST /api/v1/feedback (anonymous)" do
    test "creates feedback with an optional email", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/feedback", %{
          "message" => "I really like the recipe browser!",
          "email" => "guest@example.com"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["message"] == "I really like the recipe browser!"
      assert data["email"] == "guest@example.com"
      assert is_nil(data["user_id"])
      assert data["submitted_at"]
    end

    test "422 when message is too short", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/feedback", %{"message" => "too short"})

      assert %{"errors" => %{"fields" => %{"message" => [_ | _]}}} =
               json_response(conn, 422)
    end
  end

  describe "POST /api/v1/feedback (authenticated)" do
    setup :register_and_log_in_api_user

    test "attributes feedback to the caller and uses the account email", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/v1/feedback", %{
          "message" => "Logged-in feedback should attach my account.",
          "email" => "spoofed@example.com"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["user_id"] == user.id
      assert data["email"] == user.email
      refute data["email"] == "spoofed@example.com"
    end
  end

  test "persists the feedback row", %{conn: conn} do
    post(conn, ~p"/api/v1/feedback", %{"message" => "This gets saved to the database."})

    assert [%Feedback.Feedback{message: "This gets saved to the database."}] =
             Feedback.list_feedbacks()
  end
end
