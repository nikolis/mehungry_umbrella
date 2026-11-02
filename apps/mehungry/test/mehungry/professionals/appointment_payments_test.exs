defmodule Mehungry.Professionals.AppointmentPaymentsTest do
  use Mehungry.DataCase, async: false

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals

  @return_urls [success_url: "https://app.test/ok", cancel_url: "https://app.test/no"]

  setup do
    prev = Application.get_env(:mehungry, :stripe_payment_client)

    Application.put_env(
      :mehungry,
      :stripe_payment_client,
      Mehungry.Billing.StripePaymentClientStub
    )

    Application.put_env(:mehungry, :stripe_stub_pid, self())

    # Consultation payments are shadowed off by default; this suite covers the
    # (still-present) charge flow, so opt it back on for these tests only.
    prev_enabled = Application.get_env(:mehungry, :consultation_payments_enabled)
    Application.put_env(:mehungry, :consultation_payments_enabled, true)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:mehungry, :stripe_payment_client, prev),
        else: Application.delete_env(:mehungry, :stripe_payment_client)

      if is_nil(prev_enabled),
        do: Application.delete_env(:mehungry, :consultation_payments_enabled),
        else: Application.put_env(:mehungry, :consultation_payments_enabled, prev_enabled)

      Application.delete_env(:mehungry, :stripe_stub_pid)

      for name <-
            ~w(create_consultation_checkout capture_payment_intent cancel_payment_intent refund_payment)a do
        Application.delete_env(:mehungry, :"stripe_stub_#{name}")
      end
    end)

    professional = user_fixture()
    client = user_fixture()

    rows =
      for dow <- 0..6, do: %{day_of_week: dow, start_time: ~T[09:00:00], end_time: ~T[11:00:00]}

    {:ok, _} = Professionals.replace_availabilities(professional.id, rows)

    %{professional: professional, client: client}
  end

  # A profile that can charge: Connect onboarding complete. The *amount* comes
  # from the booked service (per-service pricing), not the profile.
  defp payable_profile(professional) do
    {:ok, profile} =
      Professionals.create_professional_profile(%{
        user_id: professional.id,
        specialization: "Dietitian",
        display_name: "Dr. Pay"
      })

    {:ok, profile} =
      Professionals.update_professional_stripe(profile, %{
        stripe_connect_account_id: "acct_test_123",
        stripe_charges_enabled: true
      })

    profile
  end

  # A paid session service (price in cents).
  defp paid_service(professional, price_cents \\ 5000) do
    {:ok, service} =
      Professionals.create_service(%{
        professional_id: professional.id,
        kind: "session",
        name: "Initial consultation",
        price_cents: price_cents,
        currency: "eur",
        duration_minutes: 60
      })

    service
  end

  defp open_slot(professional) do
    today = Date.utc_today()
    [slot | _] = Professionals.available_slots(professional.id, today, Date.add(today, 7))
    slot
  end

  defp request_paid(ctx, service, opts \\ []) do
    slot = open_slot(ctx.professional)
    opts = Keyword.merge([professional_service_id: service.id] ++ @return_urls, opts)
    Professionals.request_appointment(ctx.professional.id, ctx.client.id, slot, opts)
  end

  test "platform_fee_cents is 5% by default" do
    assert Professionals.platform_fee_cents(5000) == 250
    assert Professionals.platform_fee_cents(999) == 50
  end

  test "fee_vat_cents extracts the 24%-inclusive VAT slice from the fee" do
    # 250c fee, VAT-inclusive at 24%: net 202c, VAT 48c.
    assert Professionals.fee_vat_cents(250) == 48
  end

  test "requesting a payable slot for a paid service creates a pending payment + Checkout redirect",
       ctx do
    _profile = payable_profile(ctx.professional)
    service = paid_service(ctx.professional)

    assert {:ok, appt, url} = request_paid(ctx, service)

    assert url == "https://checkout.stripe.test/session"
    assert_received {:stripe, :create_consultation_checkout, opts}
    assert opts[:amount_cents] == 5000
    assert opts[:application_fee_cents] == 250
    assert opts[:destination_account] == "acct_test_123"

    payment = Professionals.get_payment_for_appointment(appt.id)
    assert payment.status == "pending"
    assert payment.stripe_checkout_session_id == "cs_test_123"
    assert payment.platform_fee_cents == 250
    assert payment.fee_vat_cents == 48
    assert payment.professional_service_id == service.id
  end

  test "the free intro service never charges (2-tuple, no payment)", ctx do
    _profile = payable_profile(ctx.professional)
    {:ok, intro} = Professionals.ensure_intro_service(ctx.professional.id)

    assert {:ok, appt} = request_paid(ctx, intro)
    assert Professionals.get_payment_for_appointment(appt.id) == nil
    refute_received {:stripe, :create_consultation_checkout, _}
  end

  test "a non-payable (not-onboarded) profile keeps the 2-tuple, no payment", ctx do
    {:ok, _profile} =
      Professionals.create_professional_profile(%{
        user_id: ctx.professional.id,
        specialization: "Dietitian"
      })

    service = paid_service(ctx.professional)

    assert {:ok, appt} = request_paid(ctx, service)
    assert Professionals.get_payment_for_appointment(appt.id) == nil
    refute_received {:stripe, :create_consultation_checkout, _}
  end

  test "accepting an authorized booking captures the hold", ctx do
    _profile = payable_profile(ctx.professional)
    service = paid_service(ctx.professional)

    {:ok, appt, _url} = request_paid(ctx, service)

    # Simulate the checkout.session.completed webhook.
    {:ok, _} = Professionals.mark_payment_authorized("cs_test_123", "pi_test_1")
    assert Professionals.get_payment_for_appointment(appt.id).status == "authorized"

    assert {:ok, accepted} = Professionals.accept_appointment(appt)
    assert accepted.status == "accepted"
    assert_received {:stripe, :capture_payment_intent, "pi_test_1"}

    payment = Professionals.get_payment_for_appointment(appt.id)
    assert payment.status == "paid"
    assert payment.stripe_charge_id == "ch_test_pi_test_1"
  end

  test "cannot accept a booking that is not yet authorized", ctx do
    _profile = payable_profile(ctx.professional)
    service = paid_service(ctx.professional)

    {:ok, appt, _url} = request_paid(ctx, service)

    # Still "pending" — client hasn't completed checkout.
    assert {:error, :payment_not_authorized} = Professionals.accept_appointment(appt)
  end

  test "failed capture blocks acceptance", ctx do
    _profile = payable_profile(ctx.professional)
    service = paid_service(ctx.professional)

    {:ok, appt, _url} = request_paid(ctx, service)
    {:ok, _} = Professionals.mark_payment_authorized("cs_test_123", "pi_test_1")

    Application.put_env(:mehungry, :stripe_stub_capture_payment_intent, fn _ ->
      {:error, :card_expired}
    end)

    assert {:error, {:capture_failed, :card_expired}} = Professionals.accept_appointment(appt)
    assert Professionals.get_appointment!(appt.id).status == "requested"
  end

  test "declining an authorized booking releases the hold", ctx do
    _profile = payable_profile(ctx.professional)
    service = paid_service(ctx.professional)

    {:ok, appt, _url} = request_paid(ctx, service)
    {:ok, _} = Professionals.mark_payment_authorized("cs_test_123", "pi_test_1")

    assert {:ok, declined} = Professionals.decline_appointment(appt)
    assert declined.status == "declined"
    assert_received {:stripe, :cancel_payment_intent, "pi_test_1"}
    assert Professionals.get_payment_for_appointment(appt.id).status == "canceled"
  end

  # ── Refund tiers (owner policy 2026-11-02) ──────────────────────────────────

  defp paid_appointment(ctx, scheduled_at) do
    {:ok, appt} =
      Professionals.create_appointment(%{
        professional_id: ctx.professional.id,
        client_id: ctx.client.id,
        scheduled_at: scheduled_at,
        ends_at: NaiveDateTime.add(scheduled_at, 3600),
        title: "C",
        status: "accepted"
      })

    {:ok, _} =
      Professionals.create_appointment_payment(%{
        appointment_id: appt.id,
        amount_cents: 5000,
        currency: "eur",
        platform_fee_cents: 250,
        status: "paid",
        stripe_payment_intent_id: "pi_paid_#{appt.id}"
      })

    appt
  end

  test "cancelling >= 24h out fully refunds", ctx do
    appt = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 5 * 24 * 3600))

    assert {:ok, cancelled} = Professionals.cancel_appointment(appt)
    assert cancelled.status == "cancelled"
    assert_received {:stripe, :refund_payment, {pi, opts}}
    assert pi == "pi_paid_#{appt.id}"
    # Full refund → no :amount_cents (whole charge reversed).
    refute Keyword.has_key?(opts, :amount_cents)
    assert Professionals.get_payment_for_appointment(appt.id).status == "refunded"
  end

  test "cancelling within 4h–24h refunds 50%", ctx do
    appt = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 10 * 3600))

    assert {:ok, _} = Professionals.cancel_appointment(appt)
    assert_received {:stripe, :refund_payment, {_pi, opts}}
    assert opts[:amount_cents] == 2500

    payment = Professionals.get_payment_for_appointment(appt.id)
    assert payment.status == "partially_refunded"
    assert payment.refunded_amount_cents == 2500
  end

  test "cancelling inside 4h does not refund", ctx do
    appt = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 3600))

    assert {:ok, _} = Professionals.cancel_appointment(appt)
    refute_received {:stripe, :refund_payment, _}
    assert Professionals.get_payment_for_appointment(appt.id).status == "paid"
  end

  test "marking an accepted booking as no-show retains the payment in full", ctx do
    appt = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 3600))

    assert {:ok, ns} = Professionals.mark_no_show(appt)
    assert ns.status == "no_show"
    refute_received {:stripe, :refund_payment, _}
    assert Professionals.get_payment_for_appointment(appt.id).status == "paid"
  end

  # ── Nutritionist-initiated cancellation = always a FULL refund ───────────────

  test "nutritionist cancel of a paid booking fully refunds even inside the <4h window", ctx do
    # 1h out would be 0% for a *client* cancel, but the nutritionist cancel is full.
    appt = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 3600))

    assert {:ok, cancelled} = Professionals.cancel_appointment_by_professional(appt)
    assert cancelled.status == "cancelled"
    assert_received {:stripe, :refund_payment, {_pi, opts}}
    refute Keyword.has_key?(opts, :amount_cents)
    assert Professionals.get_payment_for_appointment(appt.id).status == "refunded"
  end

  test "nutritionist cancel of an authorized (uncaptured) booking releases the hold", ctx do
    _profile = payable_profile(ctx.professional)
    service = paid_service(ctx.professional)
    {:ok, appt, _url} = request_paid(ctx, service)
    {:ok, _} = Professionals.mark_payment_authorized("cs_test_123", "pi_test_1")

    assert {:ok, _} = Professionals.cancel_appointment_by_professional(appt)
    assert_received {:stripe, :cancel_payment_intent, "pi_test_1"}
    assert Professionals.get_payment_for_appointment(appt.id).status == "canceled"
  end

  # ── Client refund preview (tiered) ──────────────────────────────────────────

  test "client_cancellation_refund_cents returns full / half / zero by window", ctx do
    full = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 48 * 3600))
    half = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 10 * 3600))
    none = paid_appointment(ctx, NaiveDateTime.add(NaiveDateTime.utc_now(), 3600))

    assert Professionals.client_cancellation_refund_cents(full) == 5000
    assert Professionals.client_cancellation_refund_cents(half) == 2500
    assert Professionals.client_cancellation_refund_cents(none) == 0
  end
end
