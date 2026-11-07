defmodule MehungryWeb.Api.V1.ProgressTest do
  @moduledoc "Self-tracking progress journal (spec §19)."
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.Professionals
  alias Mehungry.Progress

  setup :register_and_log_in_api_user

  describe "auth" do
    test "all routes require a bearer token" do
      conn = build_conn()

      assert conn |> get(~p"/api/v1/me/progress/periods") |> json_response(401)
      assert conn |> post(~p"/api/v1/me/progress/reset") |> json_response(401)
    end
  end

  describe "GET /me/progress/periods" do
    test "bootstraps the journal and lists periods", %{conn: conn} do
      body = conn |> get(~p"/api/v1/me/progress/periods") |> json_response(200)

      assert %{"data" => %{"active_period_id" => id, "periods" => [period]}} = body
      assert period["id"] == id
      assert period["kind"] == "self"
      assert period["active"] == true
      assert period["self_logging"] == true
      assert period["started_on"] == Date.to_iso8601(Date.utc_today())
    end
  end

  describe "period detail + configuration" do
    test "show returns the dashboard payload; 404 cross-user", %{conn: conn, user: user} do
      {:ok, period} = Progress.ensure_active_period(user.id)

      {:ok, _} =
        Progress.configure_period(user.id, period.id, %{
          height_m: 1.75,
          goals: %{"weight_kg" => 72}
        })

      {:ok, _} = Progress.log_entry(user.id, period.id, %{"weight_kg" => 80})

      body = conn |> get(~p"/api/v1/me/progress/periods/#{period.id}") |> json_response(200)

      assert %{"data" => data} = body
      assert data["id"] == period.id
      assert data["context"]["goals"] == %{"weight_kg" => 72.0}
      assert [point] = data["history"]
      assert point["source"] == "self"
      assert point["weight_kg"] == 80.0
      # Derived server-side from the height snapshot.
      assert point["bmi"] == 26.1
      assert is_list(data["metrics"]) and length(data["metrics"]) == 6
      assert data["comparison"] == nil
      assert data["photo_markers"] == []

      # IDOR: another user's period is a plain 404.
      other = AccountsFixtures.user_fixture()
      {:ok, other_period} = Progress.ensure_active_period(other.id)

      assert conn
             |> get(~p"/api/v1/me/progress/periods/#{other_period.id}")
             |> json_response(404)
    end

    test "PATCH configures a self period; goals normalized", %{conn: conn, user: user} do
      {:ok, period} = Progress.ensure_active_period(user.id)

      body =
        conn
        |> patch(~p"/api/v1/me/progress/periods/#{period.id}", %{
          "period" => %{
            "tracked_metrics" => ["weight_kg", "waist_cm"],
            "goals" => %{"waist_cm" => "85", "bogus" => 1},
            "height_m" => 1.8,
            "sex" => "female",
            "age" => 30
          }
        })
        |> json_response(200)

      assert %{"data" => data} = body
      assert data["tracked_metrics"] == ["weight_kg", "waist_cm"]
      assert data["goals"] == %{"waist_cm" => 85.0}
      assert data["height_m"] == 1.8
    end

    test "POST /periods is an idempotent bootstrap with optional config", %{conn: conn} do
      body =
        conn
        |> post(~p"/api/v1/me/progress/periods", %{
          "period" => %{"goals" => %{"weight_kg" => 70}}
        })
        |> json_response(200)

      assert %{"data" => %{"id" => id, "goals" => %{"weight_kg" => 70.0}}} = body

      # Second call returns the same active period.
      body2 = conn |> post(~p"/api/v1/me/progress/periods", %{}) |> json_response(200)
      assert body2["data"]["id"] == id
    end
  end

  describe "POST /me/progress/reset" do
    test "closes the active period and opens a fresh one", %{conn: conn, user: user} do
      {:ok, period} = Progress.ensure_active_period(user.id)

      body = conn |> post(~p"/api/v1/me/progress/reset") |> json_response(200)

      assert %{"data" => %{"closed" => closed, "opened" => opened}} = body
      assert closed["id"] == period.id
      assert closed["ended_on"] == Date.to_iso8601(Date.utc_today())
      assert opened["active"] == true
      assert opened["id"] != period.id
    end
  end

  describe "sharing" do
    test "share without a nutritionist → 422; with one → toggles", %{conn: conn, user: user} do
      {:ok, period} = Progress.ensure_active_period(user.id)

      assert conn
             |> post(~p"/api/v1/me/progress/periods/#{period.id}/share")
             |> json_response(422)

      pro = AccountsFixtures.user_fixture()
      {:ok, inv} = Professionals.invite_client(pro.id, user.email)
      {:ok, _} = Professionals.accept_invitation(inv.id, user.id)
      # Acceptance opened an aligned period; share that one.
      active = Progress.active_period(user.id)

      body =
        conn
        |> post(~p"/api/v1/me/progress/periods/#{active.id}/share")
        |> json_response(200)

      assert body["data"]["shared_with_nutritionist"] == true

      body =
        conn
        |> delete(~p"/api/v1/me/progress/periods/#{active.id}/share")
        |> json_response(200)

      assert body["data"]["shared_with_nutritionist"] == false
    end
  end

  describe "entries" do
    test "upsert by date, list, delete; aligned period rejected", %{conn: conn, user: user} do
      {:ok, period} = Progress.ensure_active_period(user.id)

      body =
        conn
        |> post(~p"/api/v1/me/progress/entries", %{
          "period_id" => period.id,
          "entry" => %{"entry_date" => "2026-11-01", "weight_kg" => 80, "note" => "day 1"}
        })
        |> json_response(200)

      assert %{"data" => %{"id" => entry_id, "weight_kg" => 80.0, "note" => "day 1"}} = body

      # Same date again → same entry, updated.
      body =
        conn
        |> post(~p"/api/v1/me/progress/entries", %{
          "period_id" => period.id,
          "entry" => %{"entry_date" => "2026-11-01", "weight_kg" => 79.5}
        })
        |> json_response(200)

      assert body["data"]["id"] == entry_id
      assert body["data"]["weight_kg"] == 79.5

      body =
        conn |> get(~p"/api/v1/me/progress/periods/#{period.id}/entries") |> json_response(200)

      assert [%{"id" => ^entry_id, "photos" => []}] = body["data"]

      assert conn
             |> delete(~p"/api/v1/me/progress/entries/#{entry_id}")
             |> response(204)

      # Logging into a nutritionist-aligned period is rejected (422).
      pro = AccountsFixtures.user_fixture()
      {:ok, aligned} = Progress.on_nutritionist_assigned(user.id, pro.id)

      assert conn
             |> post(~p"/api/v1/me/progress/entries", %{
               "period_id" => aligned.id,
               "entry" => %{"weight_kg" => 80}
             })
             |> json_response(422)
    end

    test "cross-user entry delete is 404", %{conn: conn} do
      other = AccountsFixtures.user_fixture()
      {:ok, other_period} = Progress.ensure_active_period(other.id)
      {:ok, entry} = Progress.log_entry(other.id, other_period.id, %{"weight_kg" => 70})

      assert conn
             |> delete(~p"/api/v1/me/progress/entries/#{entry.id}")
             |> json_response(404)
    end
  end

  describe "photos" do
    test "attach resolves the upload key to a public URL", %{conn: conn, user: user} do
      {:ok, period} = Progress.ensure_active_period(user.id)
      {:ok, entry} = Progress.log_entry(user.id, period.id, %{"weight_kg" => 80})

      body =
        conn
        |> post(~p"/api/v1/me/progress/photos", %{
          "entry_id" => entry.id,
          "upload_id" => "progress_photos/test.jpg"
        })
        |> json_response(200)

      assert %{"data" => %{"id" => _, "url" => url}} = body
      assert String.contains?(url, "progress_photos/test.jpg")
      assert String.starts_with?(url, "https://")

      # Missing upload_id → 400.
      assert conn
             |> post(~p"/api/v1/me/progress/photos", %{"entry_id" => entry.id})
             |> json_response(400)
    end

    test "presign accepts the progress_photo kind", %{conn: conn} do
      # Storage isn't configured in tests, so both an unknown kind and a valid
      # one end in 400 — but with different details: the unknown kind fails the
      # kind validation, progress_photo gets past it to the not-configured error.
      unknown =
        conn |> post(~p"/api/v1/uploads/presign", %{"kind" => "nope"}) |> json_response(400)

      valid =
        conn
        |> post(~p"/api/v1/uploads/presign", %{"kind" => "progress_photo"})
        |> json_response(400)

      assert valid["errors"]["detail"] =~ "not configured"
      refute unknown["errors"]["detail"] =~ "not configured"
    end
  end

  describe "§18 regression" do
    test "GET /me/progress (nutritionist-sourced) is unchanged once consent is granted", %{
      conn: conn,
      user: user
    } do
      # GET /me/progress now requires an Art. 9 consent (health data); grant it,
      # then confirm the §18 shape is otherwise unchanged.
      {:ok, _} = Professionals.grant_clinical_consent(user.id, Professionals.clinical_consent_version())

      body = conn |> get(~p"/api/v1/me/progress") |> json_response(200)

      assert %{"data" => %{"metrics" => metrics, "context" => _, "history" => []}} = body
      assert Enum.any?(metrics, &(&1["key"] == "weight_kg"))
    end
  end
end
