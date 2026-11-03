defmodule MehungryWeb.NutritionistLive.AnalyticsLiveTest do
  @moduledoc """
  Smoke tests for the Earnings & pipeline page (`/nutritionist/analytics`):
  it renders for a fresh pro (empty state), shows revenue once a payment lands,
  survives range/dimension switching, and is gated to nutritionists.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Subscriptions}

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.grant_nutritionist(nutritionist.id)
    %{conn: log_in_user(conn, nutritionist), nutritionist: nutritionist, client: client}
  end

  defp seed_paid(prof_id, client_id) do
    sched = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600) |> NaiveDateTime.truncate(:second)

    {:ok, appt} =
      Professionals.create_appointment(%{
        professional_id: prof_id,
        client_id: client_id,
        scheduled_at: sched,
        ends_at: NaiveDateTime.add(sched, 3600),
        title: "C",
        status: "accepted"
      })

    {:ok, _} =
      Professionals.create_appointment_payment(%{
        appointment_id: appt.id,
        professional_id: prof_id,
        client_id: client_id,
        amount_cents: 5000,
        currency: "eur",
        platform_fee_cents: 250,
        status: "paid"
      })
  end

  test "a fresh pro sees the empty-revenue state + the KPI tiles", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist/analytics")

    assert html =~ "Earnings &amp; pipeline"
    assert html =~ "Net earned"
    assert html =~ "In flight"
    assert html =~ "Pending requests"
    assert html =~ "No revenue recorded yet"
  end

  test "revenue shows once a consultation is captured", %{
    conn: conn,
    nutritionist: n,
    client: c
  } do
    seed_paid(n.id, c.id)

    # Default range is "this month"; the just-captured payment lands in it.
    {:ok, _view, html} = live(conn, "/nutritionist/analytics")

    assert html =~ "€47.50"
    refute html =~ "No revenue recorded yet"
  end

  test "switching time range and breakdown dimension re-renders", %{
    conn: conn,
    nutritionist: n,
    client: c
  } do
    seed_paid(n.id, c.id)
    {:ok, view, _html} = live(conn, "/nutritionist/analytics")

    assert render_click(view, "set_range", %{"range" => "all"}) =~ "All time"
    assert render_click(view, "set_dimension", %{"dim" => "outcome"}) =~ "Where it came from"
    assert render_click(view, "set_dimension", %{"dim" => "returning"}) =~ "Net earned"
  end

  test "a non-nutritionist is redirected away", %{conn: conn} do
    plain = Mehungry.AccountsFixtures.user_fixture()

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(log_in_user(conn, plain), "/nutritionist/analytics")
  end
end
