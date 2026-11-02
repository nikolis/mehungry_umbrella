defmodule Mehungry.Professionals.AppointmentPayment do
  @moduledoc """
  Durable, auditable payment record for a paid consultation booking.

  One row per `Appointment` (unique). It tracks a Stripe Connect **destination
  charge with manual capture**: the client's card is authorized when they book,
  captured when the nutritionist accepts, and voided/refunded otherwise. The
  money figures (`amount_cents`, `platform_fee_cents`, `fee_vat_cents`,
  `currency`, `professional_service_id`) are snapshots taken at booking time so
  later service/profile edits never rewrite history.

  `platform_fee_cents` is our flat 5% commission; it is **VAT-inclusive** (owner
  decision 2026-11-02 — `docs/.../nutritionist_payments_build_plan.md` §4.4), so
  `fee_vat_cents` records the VAT slice *contained within* that fee (not added on
  top). For a domestic Greek nutritionist that is `fee - round(fee / 1.24)`; for
  an other-EU reverse-charge account it is 0 (they self-account). Jurisdiction is
  not yet modelled, so this is computed best-effort at booking — see
  `Mehungry.Professionals.fee_vat_cents/2`.

  ## Status state machine

      pending           — Checkout session created, awaiting the client's card
      authorized        — hold placed (Stripe PI in `requires_capture`)
      paid              — captured on accept; transfer to the nutritionist made
      refunded          — full refund issued (fee + transfer reversed)
      partially_refunded — partial refund issued
      disputed          — client opened a chargeback (platform-liable)
      canceled          — hold released (declined / expired / abandoned)
      failed            — the payment failed
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending authorized paid refunded partially_refunded disputed canceled failed)

  def statuses, do: @statuses

  schema "professional_payments" do
    field :stripe_checkout_session_id, :string
    field :stripe_payment_intent_id, :string
    field :stripe_charge_id, :string
    field :stripe_account_id, :string

    field :amount_cents, :integer
    field :currency, :string
    field :platform_fee_cents, :integer
    field :fee_vat_cents, :integer, default: 0
    field :refunded_amount_cents, :integer, default: 0

    field :status, :string, default: "pending"

    field :authorized_at, :naive_datetime
    field :captured_at, :naive_datetime
    field :canceled_at, :naive_datetime
    field :refunded_at, :naive_datetime
    field :disputed_at, :naive_datetime

    field :failure_reason, :string

    belongs_to :appointment, Mehungry.Professionals.Appointment
    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :client, Mehungry.Accounts.User
    belongs_to :service, Mehungry.Professionals.ProfessionalService, foreign_key: :professional_service_id

    timestamps()
  end

  @castable [
    :appointment_id,
    :professional_id,
    :client_id,
    :professional_service_id,
    :stripe_checkout_session_id,
    :stripe_payment_intent_id,
    :stripe_charge_id,
    :stripe_account_id,
    :amount_cents,
    :currency,
    :platform_fee_cents,
    :fee_vat_cents,
    :refunded_amount_cents,
    :status,
    :authorized_at,
    :captured_at,
    :canceled_at,
    :refunded_at,
    :disputed_at,
    :failure_reason
  ]

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, @castable)
    |> validate_required([
      :appointment_id,
      :amount_cents,
      :currency,
      :platform_fee_cents,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:platform_fee_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:appointment_id)
    |> foreign_key_constraint(:appointment_id)
  end

  @doc "Net amount the nutritionist receives before Stripe processing fees."
  def net_cents(%__MODULE__{amount_cents: amount, platform_fee_cents: fee}), do: amount - fee
end
