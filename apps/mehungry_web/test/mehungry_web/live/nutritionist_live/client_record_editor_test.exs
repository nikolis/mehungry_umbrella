defmodule MehungryWeb.NutritionistLive.ClientRecordEditorTest do
  @moduledoc """
  Smoke tests for the full dietary-history editor (`:edit` only — the record is
  created from the client, so there is no user picker here): filling the typed +
  questionnaire + 24h-recall intake and a consultation note (and seeing them on
  the read-only record page), the live BMI/BMR/TDEE recompute, and the ownership
  redirect.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo, Subscriptions}
  alias Mehungry.Professionals.TutorClientAssignment

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _} =
      Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    %{conn: log_in_user(conn, nutritionist), user: nutritionist}
  end

  # A record is always reached from an assigned client; build that setup directly.
  defp record_for(professional, name) do
    client_user = Mehungry.AccountsFixtures.user_fixture()
    client_user = Repo.update!(Ecto.Changeset.change(client_user, name: name))
    Repo.insert!(%TutorClientAssignment{professional_id: professional.id, client_id: client_user.id})

    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: professional.id,
        user_id: client_user.id,
        full_name: name
      })

    {record, client_user}
  end

  test "fills intake + a note; read-only page renders them", %{conn: conn, user: user} do
    {record, _client_user} = record_for(user, "John Client")

    {:ok, edit_view, _html} = live(conn, "/nutritionist/records/#{record.id}/edit")

    # Intake: a typed field, a questionnaire detail key, and a recall key.
    edit_view
    |> form("form[phx-submit='save_intake']",
      intake: %{
        height_m: "1.75",
        weight_kg: "80",
        details: %{
          "reason_for_visit" => "Weight loss",
          "recall_24h" => %{"breakfast" => "Oats"}
        }
      }
    )
    |> render_submit()

    intake = Professionals.get_latest_intake(record.id)
    assert intake.height_m == 1.75
    assert intake.weight_kg == 80.0
    assert intake.details["reason_for_visit"] == "Weight loss"
    assert intake.details["recall_24h"]["breakfast"] == "Oats"

    # Add a consultation note, then fill it.
    render_click(edit_view, "add_note")
    [note] = Professionals.list_consultation_notes(record.id)

    edit_view
    |> form("form[phx-submit='save_note']",
      note: %{_id: note.id, visit_number: "1", modality: "phone", body: "First visit."}
    )
    |> render_submit()

    saved = Professionals.list_consultation_notes(record.id) |> hd()
    assert saved.body == "First visit."
    assert saved.modality == "phone"

    # Read-only record page shows all of it.
    {:ok, _v, html} = live(conn, "/nutritionist/records/#{record.id}")
    assert html =~ "Weight loss"
    assert html =~ "Oats"
    assert html =~ "First visit."
    assert html =~ "John Client"
  end

  test "editing the client details saves the PII fields", %{conn: conn, user: user} do
    {record, _client_user} = record_for(user, "Edit Me")

    {:ok, edit_view, _html} = live(conn, "/nutritionist/records/#{record.id}/edit")

    edit_view
    |> form("form[phx-submit='save_client']", client: %{full_name: "Edited Name", phone: "555-1234"})
    |> render_submit()

    updated = Professionals.get_client_record!(user.id, record.id)
    assert updated.full_name == "Edited Name"
    assert updated.phone == "555-1234"
    # The required association is untouched by a details edit.
    assert updated.user_id == record.user_id
  end

  test "validate_intake recomputes BMI/BMR/TDEE when a source field changes, respects an override",
       %{conn: conn, user: user} do
    {record, _client_user} = record_for(user, "Calc Client")

    {:ok, edit_view, _html} = live(conn, "/nutritionist/records/#{record.id}/edit")

    sources = %{
      "height_m" => "1.70",
      "weight_kg" => "72",
      "sex" => "female",
      "age" => "34",
      "activity_level" => "moderate"
    }

    # A *source* edit → outputs recompute and show in the form.
    html =
      render_hook(edit_view, "validate_intake", %{
        "_target" => ["intake", "weight_kg"],
        "intake" => sources
      })

    assert html =~ ~s(value="24.9")
    assert html =~ ~s(value="1452")
    assert html =~ ~s(value="#{round(1452 * 1.55)}")

    # An *output* edit (BMR typed) → the typed value is kept, not overwritten.
    html =
      render_hook(edit_view, "validate_intake", %{
        "_target" => ["intake", "bmr_kcal"],
        "intake" => Map.put(sources, "bmr_kcal", "1600")
      })

    assert html =~ ~s(value="1600")
    refute html =~ ~s(value="1452")
  end

  test "editing another professional's record redirects away", %{conn: conn} do
    other = Mehungry.AccountsFixtures.user_fixture()

    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: other.id,
        user_id: other.id,
        full_name: "Not Yours"
      })

    assert {:error, {:live_redirect, %{to: "/nutritionist/clients"}}} =
             live(conn, "/nutritionist/records/#{record.id}/edit")
  end
end
