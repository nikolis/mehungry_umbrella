defmodule Mehungry.Professionals.AnalyticsTest do
  @moduledoc """
  The Earnings & pipeline aggregates. Payments are created directly (no Stripe
  stub needed) so each test seeds a known revenue picture and asserts the SQL
  roll-ups. Net is always `amount - platform_fee - refunded` over
  `paid`/`partially_refunded`. See docs/features/professionals/analytics.md.
  """
  use Mehungry.DataCase, async: false

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals

  setup do
    %{professional: user_fixture(), client: user_fixture(), client2: user_fixture()}
  end

  # A unique, monotonically increasing per-test slot offset so appointments never
  # collide on the `professional_appointments_active_slot_unique` partial index.
  defp next_slot do
    n = Process.get(:slot_counter, 0)
    Process.put(:slot_counter, n + 1)
    NaiveDateTime.add(NaiveDateTime.utc_now(), (n + 1) * 3600) |> NaiveDateTime.truncate(:second)
  end

  # Create an appointment + its payment row for the given professional/client.
  # `attrs` carries the payment fields plus an optional `:appt_status` /
  # `:scheduled_at` for the appointment side.
  defp make_payment(prof_id, client_id, attrs) do
    appt_status = Map.get(attrs, :appt_status, "accepted")

    sched =
      case Map.get(attrs, :scheduled_at) do
        nil -> next_slot()
        given -> NaiveDateTime.truncate(given, :second)
      end

    {:ok, appt} =
      Professionals.create_appointment(%{
        professional_id: prof_id,
        client_id: client_id,
        scheduled_at: sched,
        ends_at: NaiveDateTime.add(sched, 3600),
        title: "C",
        status: appt_status
      })

    payment_attrs =
      %{
        appointment_id: appt.id,
        professional_id: prof_id,
        client_id: client_id,
        currency: "eur"
      }
      |> Map.merge(
        Map.take(attrs, [
          :amount_cents,
          :platform_fee_cents,
          :refunded_amount_cents,
          :status,
          :authorized_at,
          :captured_at,
          :professional_service_id
        ])
      )

    {:ok, payment} = Professionals.create_appointment_payment(payment_attrs)
    {appt, payment}
  end

  test "net_earnings_cents nets fee + refunds over paid/partially, range-filtered",
       %{professional: p, client: c} do
    make_payment(p.id, c.id, %{
      amount_cents: 5000,
      platform_fee_cents: 250,
      status: "paid",
      captured_at: ~N[2026-01-10 10:00:00]
    })

    make_payment(p.id, c.id, %{
      amount_cents: 2000,
      platform_fee_cents: 100,
      refunded_amount_cents: 1000,
      status: "partially_refunded",
      captured_at: ~N[2026-01-20 10:00:00]
    })

    # Excluded: an uncaptured hold and a fully refunded charge.
    make_payment(p.id, c.id, %{amount_cents: 9999, platform_fee_cents: 500, status: "authorized"})

    make_payment(p.id, c.id, %{
      amount_cents: 2000,
      platform_fee_cents: 100,
      refunded_amount_cents: 2000,
      status: "refunded",
      captured_at: ~N[2026-01-15 10:00:00]
    })

    # 4750 (5000-250) + 900 (2000-100-1000)
    assert Professionals.net_earnings_cents(p.id, :all) == 5650
    assert Professionals.professional_net_earnings_cents(p.id) == 5650

    assert Professionals.net_earnings_cents(
             p.id,
             {~N[2026-01-01 00:00:00], ~N[2026-01-31 23:59:59]}
           ) == 5650

    assert Professionals.net_earnings_cents(
             p.id,
             {~N[2026-02-01 00:00:00], ~N[2026-02-28 23:59:59]}
           ) == 0
  end

  test "in_flight_cents sums only authorized holds", %{professional: p, client: c} do
    make_payment(p.id, c.id, %{amount_cents: 6000, platform_fee_cents: 300, status: "authorized"})
    make_payment(p.id, c.id, %{amount_cents: 1000, platform_fee_cents: 50, status: "authorized"})
    make_payment(p.id, c.id, %{amount_cents: 5000, platform_fee_cents: 250, status: "paid"})

    assert Professionals.in_flight_cents(p.id) == 7000
  end

  test "count_pending_requests counts only requested appointments", %{professional: p, client: c} do
    base = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600) |> NaiveDateTime.truncate(:second)

    for {status, i} <- Enum.with_index(["requested", "requested", "accepted", "declined"]) do
      sched = NaiveDateTime.add(base, i * 3600)

      {:ok, _} =
        Professionals.create_appointment(%{
          professional_id: p.id,
          client_id: c.id,
          scheduled_at: sched,
          ends_at: NaiveDateTime.add(sched, 1800),
          title: "R",
          status: status
        })
    end

    assert Professionals.count_pending_requests(p.id) == 2
  end

  test "revenue_by_outcome buckets captured / no-show / refunded / released",
       %{professional: p, client: c} do
    # Captured on a completed consult.
    make_payment(p.id, c.id, %{amount_cents: 5000, platform_fee_cents: 250, status: "paid"})
    # Captured but client didn't show → retained, not "captured".
    make_payment(p.id, c.id, %{
      amount_cents: 1000,
      platform_fee_cents: 50,
      status: "paid",
      appt_status: "no_show"
    })

    # Partial refund: 900 stays captured, 1000 counts as refunded.
    make_payment(p.id, c.id, %{
      amount_cents: 2000,
      platform_fee_cents: 100,
      refunded_amount_cents: 1000,
      status: "partially_refunded"
    })

    # Fully refunded.
    make_payment(p.id, c.id, %{
      amount_cents: 2000,
      platform_fee_cents: 100,
      refunded_amount_cents: 2000,
      status: "refunded"
    })

    # Authorized hold that was released (declined/expired) → €0 earned, leakage.
    make_payment(p.id, c.id, %{
      amount_cents: 8000,
      platform_fee_cents: 400,
      status: "canceled",
      authorized_at: ~N[2026-01-01 00:00:00],
      appt_status: "declined"
    })

    o = Professionals.revenue_by_outcome(p.id, :all)
    assert o.captured_cents == 4750 + 900
    assert o.no_show_cents == 950
    assert o.refunded_cents == 1000 + 2000
    assert o.released_cents == 8000
  end

  test "revenue_by_service groups by service, nil service folds to its own row",
       %{professional: p, client: c} do
    {:ok, s1} =
      Professionals.create_service(%{
        professional_id: p.id,
        kind: "session",
        name: "Single session",
        price_cents: 5000,
        currency: "eur",
        duration_minutes: 60
      })

    {:ok, s2} =
      Professionals.create_service(%{
        professional_id: p.id,
        kind: "package",
        name: "4-pack",
        price_cents: 18000,
        currency: "eur",
        duration_minutes: 60
      })

    make_payment(p.id, c.id, %{
      amount_cents: 5000,
      platform_fee_cents: 250,
      status: "paid",
      professional_service_id: s1.id
    })

    make_payment(p.id, c.id, %{
      amount_cents: 18000,
      platform_fee_cents: 900,
      status: "paid",
      professional_service_id: s2.id
    })

    # No service attached → grouped under a nil service id.
    make_payment(p.id, c.id, %{amount_cents: 1000, platform_fee_cents: 50, status: "paid"})

    rows = Professionals.revenue_by_service(p.id, :all)
    # Ordered by net desc: package (17100) > single (4750) > direct (950)
    assert [first | _] = rows
    assert first.name == "4-pack"
    assert first.net_cents == 17100

    by_name = Map.new(rows, &{&1.name, &1.net_cents})
    assert by_name["Single session"] == 4750
    assert Enum.any?(rows, &(is_nil(&1.service_id) and &1.net_cents == 950))
  end

  test "revenue_new_vs_returning splits by lifetime-first capture",
       %{professional: p, client: c, client2: c2} do
    # client c: first capture 4750 (new), then 2850 + 950 (returning)
    make_payment(p.id, c.id, %{
      amount_cents: 5000,
      platform_fee_cents: 250,
      status: "paid",
      captured_at: ~N[2026-01-01 10:00:00]
    })

    make_payment(p.id, c.id, %{
      amount_cents: 3000,
      platform_fee_cents: 150,
      status: "paid",
      captured_at: ~N[2026-01-02 10:00:00]
    })

    make_payment(p.id, c.id, %{
      amount_cents: 1000,
      platform_fee_cents: 50,
      status: "paid",
      captured_at: ~N[2026-01-03 10:00:00]
    })

    # client c2: first capture 3800 (new), then 900 (returning)
    make_payment(p.id, c2.id, %{
      amount_cents: 4000,
      platform_fee_cents: 200,
      status: "paid",
      captured_at: ~N[2026-01-01 11:00:00]
    })

    make_payment(p.id, c2.id, %{
      amount_cents: 2000,
      platform_fee_cents: 100,
      refunded_amount_cents: 1000,
      status: "partially_refunded",
      captured_at: ~N[2026-01-02 11:00:00]
    })

    result = Professionals.revenue_new_vs_returning(p.id, :all)
    assert result.new_cents == 4750 + 3800
    assert result.returning_cents == 2850 + 950 + 900
    # Buckets sum to the all-time net.
    assert result.new_cents + result.returning_cents ==
             Professionals.net_earnings_cents(p.id, :all)
  end

  test "appointments_per_week counts accepted appointments by week", %{professional: p, client: c} do
    # Anchor mid-week (Monday noon) so all four land in one ISO-week bucket
    # regardless of when the test runs.
    monday = Date.beginning_of_week(Date.utc_today(), :monday)
    base = NaiveDateTime.new!(monday, ~T[12:00:00])

    for {status, i} <- Enum.with_index(["accepted", "accepted", "accepted", "requested"]) do
      sched = NaiveDateTime.add(base, i * 3600)

      {:ok, _} =
        Professionals.create_appointment(%{
          professional_id: p.id,
          client_id: c.id,
          scheduled_at: sched,
          ends_at: NaiveDateTime.add(sched, 1800),
          title: "A",
          status: status
        })
    end

    series = Professionals.appointments_per_week(p.id, 8)
    assert Enum.reduce(series, 0, &(&1.count + &2)) == 3
    assert %{count: 3} = List.last(series)
  end

  test "zero-data returns zeros and empty lists", %{professional: p} do
    assert Professionals.net_earnings_cents(p.id, :all) == 0
    assert Professionals.in_flight_cents(p.id) == 0
    assert Professionals.count_pending_requests(p.id) == 0
    assert Professionals.revenue_per_period(p.id, :all, :month) == []
    assert Professionals.appointments_per_week(p.id, 8) == []
    assert Professionals.revenue_by_service(p.id, :all) == []

    assert Professionals.revenue_by_outcome(p.id, :all) == %{
             captured_cents: 0,
             no_show_cents: 0,
             refunded_cents: 0,
             released_cents: 0
           }

    assert Professionals.revenue_new_vs_returning(p.id, :all) == %{
             new_cents: 0,
             returning_cents: 0
           }
  end
end
