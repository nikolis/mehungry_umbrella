defmodule MehungryWeb.NutritionistLive.PaymentsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Subscriptions}

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})
    %{conn: log_in_user(conn, nutritionist), nutritionist: nutritionist}
  end

  test "renders the obligation banner and seeds the free intro", %{conn: conn, nutritionist: n} do
    {:ok, _view, html} = live(conn, "/nutritionist/payments")

    assert html =~ "free 15-minute intro"
    assert html =~ "Free intro"

    # The intro row was seeded on mount.
    assert Enum.any?(Professionals.list_services(n.id), &(&1.kind == "intro"))
  end

  test "adds a paid session", %{conn: conn, nutritionist: n} do
    {:ok, view, _html} = live(conn, "/nutritionist/payments")

    view |> element("button", "+ Session") |> render_click()

    html =
      view
      |> form("form", %{
        "professional_service" => %{
          "name" => "Initial consultation",
          "price_eur" => "40",
          "duration_minutes" => "60"
        }
      })
      |> render_submit()

    assert html =~ "Initial consultation"

    session = Enum.find(Professionals.list_services(n.id), &(&1.kind == "session"))
    assert session.price_cents == 4000
    assert session.duration_minutes == 60
  end

  test "adds a package with a session count", %{conn: conn, nutritionist: n} do
    {:ok, view, _html} = live(conn, "/nutritionist/payments")

    view |> element("button", "+ Package") |> render_click()

    view
    |> form("form", %{
      "professional_service" => %{
        "name" => "2-month support",
        "price_eur" => "130",
        "session_count" => "5"
      }
    })
    |> render_submit()

    package = Enum.find(Professionals.list_services(n.id), &(&1.kind == "package"))
    assert package.price_cents == 13_000
    assert package.session_count == 5
  end

  test "hides and deletes a session but never the intro", %{conn: conn, nutritionist: n} do
    {:ok, session} =
      Professionals.create_service(%{
        professional_id: n.id,
        kind: "session",
        name: "Follow-up",
        price_cents: 3000
      })

    {:ok, view, html} = live(conn, "/nutritionist/payments")

    # The intro row offers no Delete control.
    refute html =~ ~r/phx-value-id="#{intro_id(n)}"[^>]*>\s*Delete/

    view |> render_click("archive_service", %{"id" => to_string(session.id)})
    assert Professionals.get_service!(session.id).active == false

    view |> render_click("delete_service", %{"id" => to_string(session.id)})
    refute Enum.any?(Professionals.list_services(n.id), &(&1.id == session.id))

    # Deleting the intro is a no-op (guarded in the context).
    view |> render_click("delete_service", %{"id" => to_string(intro_id(n))})
    assert Enum.any?(Professionals.list_services(n.id), &(&1.kind == "intro"))
  end

  defp intro_id(n) do
    Enum.find(Professionals.list_services(n.id), &(&1.kind == "intro")).id
  end
end
