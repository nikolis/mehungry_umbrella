defmodule MehungryWeb.Api.V1.MyNutritionistTest do
  @moduledoc "Client-facing 'My nutritionist' surface (spec §18)."
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.Professionals

  setup :register_and_log_in_api_user

  defp public_nutritionist(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()

    {:ok, profile} =
      Professionals.create_professional_profile(
        Map.merge(
          %{
            user_id: user.id,
            display_name: "Maria K.",
            specialization: "Clinical dietitian",
            bio: "Short bio",
            city: "Rethymno",
            is_public: true
          },
          attrs
        )
      )

    {user, profile}
  end

  describe "directory (GET /nutritionists)" do
    test "lists public profiles with city filters", %{conn: conn} do
      {_user, profile} = public_nutritionist()

      body = conn |> get(~p"/api/v1/nutritionists") |> json_response(200)

      assert %{"data" => data, "meta" => %{"page" => 1}, "cities" => cities} = body
      assert Enum.any?(data, &(&1["professional_id"] == profile.user_id))
      assert "Rethymno" in cities
    end

    test "public profile by slug, 404 for unknown", %{conn: conn} do
      {_user, profile} = public_nutritionist()

      body = conn |> get(~p"/api/v1/nutritionists/#{profile.slug}") |> json_response(200)
      assert %{"data" => %{"slug" => slug, "payments_enabled" => _, "services" => _}} = body
      assert slug == profile.slug

      assert conn |> get(~p"/api/v1/nutritionists/does-not-exist") |> json_response(404)
    end
  end

  describe "hub (GET /me/nutritionist)" do
    test "unconnected returns empty state with pending invitations", %{conn: conn, user: user} do
      {nutritionist, _profile} = public_nutritionist()
      {:ok, _inv} = Professionals.invite_client(nutritionist.id, user.email, "join me")

      body = conn |> get(~p"/api/v1/me/nutritionist") |> json_response(200)

      assert %{
               "data" => %{
                 "connected" => false,
                 "nutritionist" => nil,
                 "pending_invitations" => [invite]
               }
             } = body

      assert invite["professional"]["professional_id"] == nutritionist.id
    end

    test "connected returns the nutritionist preview", %{conn: conn, user: user} do
      {nutritionist, profile} = public_nutritionist()
      {:ok, _inv} = Professionals.invite_client(nutritionist.id, user.email, "join me")
      [inv] = Professionals.list_pending_invitations_for_client(user.id)
      {:ok, _assignment} = Professionals.accept_invitation(inv.id, user.id)

      body = conn |> get(~p"/api/v1/me/nutritionist") |> json_response(200)

      assert %{"data" => %{"connected" => true, "nutritionist" => n}} = body
      assert n["professional_id"] == profile.user_id
      assert n["slug"] == profile.slug
    end

    test "connected even when the nutritionist has no public profile row", %{conn: conn, user: user} do
      # A nutritionist with an assignment but no ProfessionalProfile (mirrors the
      # web hub's "connected, no public profile" state — not the empty state).
      nutritionist = AccountsFixtures.user_fixture()
      {:ok, _inv} = Professionals.invite_client(nutritionist.id, user.email, "join me")
      [inv] = Professionals.list_pending_invitations_for_client(user.id)
      {:ok, _assignment} = Professionals.accept_invitation(inv.id, user.id)

      body = conn |> get(~p"/api/v1/me/nutritionist") |> json_response(200)

      assert %{"data" => %{"connected" => true, "nutritionist" => n}} = body
      assert n["professional_id"] == nutritionist.id
      assert n["slug"] == nil
      assert n["display_name"] == (nutritionist.name || nutritionist.email)
    end
  end

  describe "messages" do
    test "unconnected is 404, connected lists + sends", %{conn: conn, user: user} do
      assert conn |> get(~p"/api/v1/me/nutritionist/messages") |> json_response(404)

      {nutritionist, _profile} = public_nutritionist()
      {:ok, _inv} = Professionals.invite_client(nutritionist.id, user.email, "join me")
      [inv] = Professionals.list_pending_invitations_for_client(user.id)
      {:ok, _assignment} = Professionals.accept_invitation(inv.id, user.id)

      listed = conn |> get(~p"/api/v1/me/nutritionist/messages") |> json_response(200)
      assert %{"data" => %{"messages" => [], "nutritionist" => %{}}} = listed

      created =
        conn
        |> post(~p"/api/v1/me/nutritionist/messages", %{"body" => "Hello"})
        |> json_response(201)

      assert %{"data" => %{"body" => "Hello", "from_me" => true}} = created

      empty = conn |> post(~p"/api/v1/me/nutritionist/messages", %{"body" => ""})
      assert json_response(empty, 400)
    end
  end

  describe "appointments" do
    test "empty list, cross-tenant/unknown is 404", %{conn: conn} do
      assert %{"data" => []} = conn |> get(~p"/api/v1/me/appointments") |> json_response(200)
      assert conn |> get(~p"/api/v1/me/appointments/999999") |> json_response(404)
      assert conn |> delete(~p"/api/v1/me/appointments/999999") |> json_response(404)
    end

    test "booking an unavailable slot is a clean 422", %{conn: conn} do
      {nutritionist, _profile} = public_nutritionist()

      conn =
        post(conn, ~p"/api/v1/me/appointments", %{
          "professional_id" => nutritionist.id,
          "scheduled_at" => "2099-01-01T12:00:00Z"
        })

      assert json_response(conn, 422)
    end

    test "a malformed scheduled_at is a 400", %{conn: conn} do
      {nutritionist, _profile} = public_nutritionist()

      conn =
        post(conn, ~p"/api/v1/me/appointments", %{
          "professional_id" => nutritionist.id,
          "scheduled_at" => "not-a-date"
        })

      assert json_response(conn, 400)
    end

    test "a malformed professional_id is a 400", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/me/appointments", %{
          "professional_id" => "abc",
          "scheduled_at" => "2099-01-01T12:00:00Z"
        })

      assert json_response(conn, 400)
    end

    test "a valid id for a professional with no profile is a 404", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/me/appointments", %{
          "professional_id" => 9_999_999,
          "scheduled_at" => "2099-01-01T12:00:00Z"
        })

      assert json_response(conn, 404)
    end
  end

  describe "onboarding questionnaire" do
    test "404 when the nutritionist keeps no client file for the user", %{conn: conn} do
      {nutritionist, _profile} = public_nutritionist()
      assert conn |> get(~p"/api/v1/nutritionists/#{nutritionist.id}/onboarding") |> json_response(404)
    end
  end

  describe "progress (GET /me/progress)" do
    test "403 consent_required without an active clinical-data consent", %{conn: conn} do
      body = conn |> get(~p"/api/v1/me/progress") |> json_response(403)
      assert %{"errors" => %{"detail" => "consent_required"}} = body
    end

    test "returns the metric list and an empty history once consent is granted", %{
      conn: conn,
      user: user
    } do
      {:ok, _} = Professionals.grant_clinical_consent(user.id, Professionals.clinical_consent_version())

      body = conn |> get(~p"/api/v1/me/progress") |> json_response(200)
      assert %{"data" => %{"metrics" => metrics, "history" => [], "context" => %{}}} = body
      assert Enum.any?(metrics, &(&1["key"] == "weight_kg"))
    end
  end

  describe "clinical-data consent (GDPR Art. 9)" do
    test "hub reports consent null until granted, then the record", %{conn: conn} do
      assert %{"data" => %{"consent" => nil}} =
               conn |> get(~p"/api/v1/me/nutritionist") |> json_response(200)

      granted =
        conn
        |> post(~p"/api/v1/me/nutritionist/consent", %{
          "version" => Professionals.clinical_consent_version()
        })
        |> json_response(200)

      assert %{"data" => %{"consent" => %{"granted" => true, "version" => v, "granted_at" => _}}} =
               granted

      assert v == Professionals.clinical_consent_version()

      assert %{"data" => %{"consent" => %{"granted" => true}}} =
               conn |> get(~p"/api/v1/me/nutritionist") |> json_response(200)
    end

    test "granting is idempotent (no duplicate active record)", %{conn: conn, user: user} do
      version = Professionals.clinical_consent_version()
      path = ~p"/api/v1/me/nutritionist/consent"

      assert conn |> post(path, %{"version" => version}) |> json_response(200)
      assert conn |> post(path, %{"version" => version}) |> json_response(200)
      assert Professionals.clinical_consent_granted?(user.id)
    end

    test "a stale version is a 422 consent_version_mismatch", %{conn: conn} do
      body =
        conn
        |> post(~p"/api/v1/me/nutritionist/consent", %{"version" => "1999-01"})
        |> json_response(422)

      assert %{"errors" => %{"detail" => "consent_version_mismatch"}} = body
    end

    test "withdrawing re-gates the clinical surface", %{conn: conn, user: user} do
      {:ok, _} = Professionals.grant_clinical_consent(user.id, Professionals.clinical_consent_version())
      assert conn |> get(~p"/api/v1/me/progress") |> json_response(200)

      assert conn |> delete(~p"/api/v1/me/nutritionist/consent") |> response(204)
      refute Professionals.clinical_consent_granted?(user.id)

      assert %{"errors" => %{"detail" => "consent_required"}} =
               conn |> get(~p"/api/v1/me/progress") |> json_response(403)
    end

    test "withdrawing with no active consent is an idempotent 204", %{conn: conn} do
      assert conn |> delete(~p"/api/v1/me/nutritionist/consent") |> response(204)
    end
  end
end
