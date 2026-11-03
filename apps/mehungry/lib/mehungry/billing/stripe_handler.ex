defmodule Mehungry.Billing.StripeHandler do
  @moduledoc """
  Thin wrapper around Stripe's REST API using HTTPoison.
  Handles checkout session creation, billing portal, and webhook event processing.

  Required env vars:
    STRIPE_SECRET_KEY       — sk_live_... or sk_test_...
    STRIPE_WEBHOOK_SECRET   — whsec_...
    STRIPE_PRO_PRICE_ID     — price_... (monthly Pro plan created in Stripe dashboard)
    STRIPE_PRO_YEARLY_PRICE_ID — price_... (yearly Pro plan)
  """

  require Logger
  alias Mehungry.Subscriptions

  @stripe_api "https://api.stripe.com/v1"

  # ── Checkout ──────────────────────────────────────────────────────────────────

  @doc """
  Creates a Stripe Checkout Session for a subscription.

  `tier` is the target subscription tier ("m3hungry_plus" or "pro") and is stored
  in the session metadata so the `checkout.session.completed` webhook can activate
  the correct tier. Defaults to "m3hungry_plus" (consumer premium).

  Returns {:ok, checkout_url} or {:error, reason}.
  """
  def create_checkout_session(
        user_id,
        user_email,
        price_id,
        success_url,
        cancel_url,
        tier \\ "m3hungry_plus"
      ) do
    params = %{
      "mode" => "subscription",
      "customer_email" => user_email,
      "line_items[0][price]" => price_id,
      "line_items[0][quantity]" => "1",
      "success_url" => success_url,
      "cancel_url" => cancel_url,
      "metadata[user_id]" => to_string(user_id),
      "metadata[tier]" => tier,
      "subscription_data[metadata][user_id]" => to_string(user_id),
      "subscription_data[metadata][tier]" => tier
    }

    case post("/checkout/sessions", params) do
      {:ok, %{"url" => url}} -> {:ok, url}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a Stripe Billing Portal session so subscribers can manage/cancel.
  Returns {:ok, portal_url} or {:error, reason}.
  """
  def create_billing_portal_session(stripe_customer_id, return_url) do
    params = %{
      "customer" => stripe_customer_id,
      "return_url" => return_url
    }

    case post("/billing_portal/sessions", params) do
      {:ok, %{"url" => url}} -> {:ok, url}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Connect (nutritionist payouts — minimal onboarding slice) ─────────────────

  @doc """
  Create an Accounts-v2 connected account for a nutritionist (Express dashboard)
  so they can receive payouts. Returns `{:ok, account_id}` or `{:error, reason}`.

  We keep the destination-charge + `on_behalf_of` flow where the nutritionist is
  the merchant of record, so the account gets **both** configurations:

    * `merchant` — requests the `card_payments` capability (MoR for the charge),
    * `recipient` — requests `stripe_balance.stripe_transfers` (receives the
      destination transfer).

  Responsibilities are platform-owned (`fees_collector`/`losses_collector =
  application`), as required for destination charges: we carry negative-balance
  and dispute liability. MCC/industry is left to the nutritionist's onboarding
  industry selection (non-medical wellness coaching) unless `:connect_account_mcc`
  is explicitly set — Stripe has no numeric "wellness coaching" code and a forced
  one must match the chosen industry or it's rejected.
  """
  def create_connect_account(email) do
    body =
      %{
        "contact_email" => email,
        "dashboard" => "express",
        "defaults" => %{
          "responsibilities" => %{
            "fees_collector" => "application",
            "losses_collector" => "application"
          }
        },
        "identity" => %{"country" => connect_account_country()},
        "configuration" => %{
          "merchant" => merchant_configuration(),
          "recipient" => %{
            "capabilities" => %{
              "stripe_balance" => %{"stripe_transfers" => %{"requested" => true}}
            }
          }
        },
        "include" => [
          "configuration.merchant",
          "configuration.recipient",
          "identity",
          "requirements"
        ]
      }

    case post_v2("/core/accounts", body) do
      {:ok, %{"id" => account_id}} -> {:ok, account_id}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # Merchant config requests card_payments; an optional numeric MCC is nested
  # under it when `:connect_account_mcc` is set.
  defp merchant_configuration do
    base = %{"capabilities" => %{"card_payments" => %{"requested" => true}}}

    case opt(:connect_account_mcc) do
      nil -> base
      mcc -> Map.put(base, "mcc", mcc)
    end
  end

  defp connect_account_country do
    case Application.get_env(:mehungry, :connect_account_country) do
      c when is_binary(c) and c != "" -> c
      _ -> "GR"
    end
  end

  # Optional config value — nil when unset or blank so maybe_put omits the param.
  defp opt(key) do
    case Application.get_env(:mehungry, key) do
      v when is_binary(v) and v != "" -> v
      _ -> nil
    end
  end

  @doc """
  Create an onboarding Account Link the nutritionist visits to complete KYC.
  `refresh_url` is used if the link expires; `return_url` when they finish.
  Returns `{:ok, onboarding_url}`.
  """
  def create_account_link(account_id, refresh_url, return_url) do
    body = %{
      "account" => account_id,
      "use_case" => %{
        "type" => "account_onboarding",
        "account_onboarding" => %{
          "refresh_url" => refresh_url,
          "return_url" => return_url,
          # Collect eventually_due up front so the nutritionist isn't bounced
          # back through onboarding for incremental requirements later.
          "collection_options" => %{"fields" => "eventually_due"}
        }
      }
    }

    case post_v2("/core/account_links", body) do
      {:ok, %{"url" => url}} -> {:ok, url}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch a connected account's onboarding/charge status (Accounts v2). Returns
  `{:ok, %{charges_enabled: bool, details_submitted: bool, payouts_enabled: bool}}`.

  `charges_enabled` keeps its stored meaning — "can be charged onto right now" —
  which for our destination + `on_behalf_of` flow needs **both** the merchant
  `card_payments` capability and the recipient `stripe_transfers` capability to
  be `active`. `payouts_enabled` reflects the recipient transfers capability;
  `details_submitted` is best-effort (true once there are no currently-due
  requirement entries).
  """
  def get_connect_account(account_id) do
    query = "?include=configuration.merchant&include=configuration.recipient&include=requirements"

    case get_v2("/core/accounts/#{account_id}#{query}") do
      {:ok, account} ->
        card_payments? = capability_active?(account, ["merchant", "card_payments"])

        transfers? =
          capability_active?(account, ["recipient", "stripe_balance", "stripe_transfers"])

        {:ok,
         %{
           charges_enabled: card_payments? and transfers?,
           payouts_enabled: transfers?,
           details_submitted: no_currently_due_requirements?(account)
         }}

      error ->
        error
    end
  end

  # Walk configuration.<config>.capabilities.<...>.status and test for "active".
  defp capability_active?(account, path) do
    get_in(account, ["configuration" | capability_status_path(path)]) == "active"
  end

  defp capability_status_path([config | rest]), do: [config, "capabilities"] ++ rest ++ ["status"]

  # No requirement entry is currently due → the account has submitted everything
  # Stripe is asking for right now.
  defp no_currently_due_requirements?(account) do
    entries = get_in(account, ["requirements", "entries"]) || []

    not Enum.any?(entries, fn entry ->
      get_in(entry, ["minimum_deadline", "status"]) == "currently_due"
    end)
  end

  # ── Connect (consultation charging — destination charge + manual capture) ─────

  @doc """
  Open a manual-capture Checkout Session for a paid consultation booking.

  The client's card is **authorized** now (`capture_method: manual`); funds are
  captured in `capture_payment_intent/1` when the nutritionist accepts, or
  released via `cancel_payment_intent/1` on decline/expiry. The charge is a
  **destination charge** (`transfer_data[destination]` + `on_behalf_of` = the
  connected account, so the nutritionist is the merchant of record and Stripe's
  processing fee comes out of their 95%) with our 5% as `application_fee_amount`.

  `opts`: `:appointment_id`, `:destination_account`, `:currency`, `:amount_cents`,
  `:application_fee_cents`, `:success_url`, `:cancel_url`, and optional
  `:customer_email`, `:product_name`. Returns `{:ok, %{url, session_id}}`.
  """
  def create_consultation_checkout(opts) do
    appointment_id = Keyword.fetch!(opts, :appointment_id)
    account = Keyword.fetch!(opts, :destination_account)

    params = %{
      "mode" => "payment",
      "customer_email" => Keyword.get(opts, :customer_email),
      "line_items[0][price_data][currency]" => Keyword.fetch!(opts, :currency),
      "line_items[0][price_data][unit_amount]" => to_string(Keyword.fetch!(opts, :amount_cents)),
      "line_items[0][price_data][product_data][name]" =>
        Keyword.get(opts, :product_name, "Consultation"),
      "line_items[0][quantity]" => "1",
      "payment_intent_data[capture_method]" => "manual",
      "payment_intent_data[application_fee_amount]" =>
        to_string(Keyword.fetch!(opts, :application_fee_cents)),
      "payment_intent_data[transfer_data][destination]" => account,
      "payment_intent_data[on_behalf_of]" => account,
      "payment_intent_data[metadata][appointment_id]" => to_string(appointment_id),
      "metadata[appointment_id]" => to_string(appointment_id),
      "success_url" => Keyword.fetch!(opts, :success_url),
      "cancel_url" => Keyword.fetch!(opts, :cancel_url)
    }

    case post("/checkout/sessions", params, idempotency_key: "appt-#{appointment_id}-session") do
      {:ok, %{"id" => id, "url" => url}} -> {:ok, %{url: url, session_id: id}}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Capture a previously-authorized consultation PaymentIntent (on accept). Returns
  `{:ok, %{charge_id: id}}` or `{:error, reason}`.
  """
  def capture_payment_intent(payment_intent_id) do
    case post("/payment_intents/#{payment_intent_id}/capture", %{},
           idempotency_key: "#{payment_intent_id}-capture"
         ) do
      {:ok, %{"id" => _} = pi} -> {:ok, %{charge_id: latest_charge_id(pi)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Cancel (void) an uncaptured consultation PaymentIntent — releases the hold."
  def cancel_payment_intent(payment_intent_id) do
    case post("/payment_intents/#{payment_intent_id}/cancel", %{}) do
      {:ok, %{"id" => _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refund a captured consultation. A **full** refund (the default) reverses our
  application fee and the transfer so the client's money is returned end-to-end.
  A **partial** refund (`amount_cents:`) returns only that amount and reverses
  the transfer proportionally; by default it does **not** refund our platform fee
  (we keep our commission on the retained portion — pass `refund_application_fee:
  true` to override). Returns `{:ok, %{refund_id: id}}`.
  """
  def refund_payment(payment_intent_id, opts \\ []) do
    amount_cents = opts[:amount_cents]
    partial? = is_integer(amount_cents)

    params =
      %{
        "payment_intent" => payment_intent_id,
        "reverse_transfer" => "true",
        "refund_application_fee" =>
          to_string(Keyword.get(opts, :refund_application_fee, not partial?))
      }
      |> maybe_put("amount", partial? && to_string(amount_cents))

    case post("/refunds", params,
           idempotency_key: refund_idempotency_key(payment_intent_id, opts)
         ) do
      {:ok, %{"id" => id}} -> {:ok, %{refund_id: id}}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Create a one-time login link to a connected account's Express dashboard."
  def create_login_link(account_id) do
    case post("/accounts/#{account_id}/login_links", %{}) do
      {:ok, %{"url" => url}} -> {:ok, url}
      {:ok, body} -> {:error, "unexpected response: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # A PI's captured charge id lives under `latest_charge` (a string id).
  defp latest_charge_id(%{"latest_charge" => id}) when is_binary(id), do: id
  defp latest_charge_id(%{"charges" => %{"data" => [%{"id" => id} | _]}}), do: id
  defp latest_charge_id(_), do: nil

  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Distinct idempotency keys for full vs partial refunds so a later partial
  # refund isn't swallowed as a replay of the full-refund request.
  defp refund_idempotency_key(pi, opts) do
    case opts[:amount_cents] do
      n when is_integer(n) -> "#{pi}-refund-#{n}"
      _ -> "#{pi}-refund"
    end
  end

  # ── Webhook ───────────────────────────────────────────────────────────────────

  @doc """
  Verifies the Stripe webhook signature and dispatches the event.
  Returns :ok or {:error, reason}.
  """
  def handle_webhook(raw_body, signature_header) do
    webhook_secret = config(:stripe_webhook_secret)

    case verify_signature(raw_body, signature_header, webhook_secret) do
      :ok ->
        case Jason.decode(raw_body) do
          {:ok, event} -> dispatch_event(event)
          {:error, _} -> {:error, :invalid_json}
        end

      error ->
        error
    end
  end

  # ── Private: event dispatch ───────────────────────────────────────────────────

  # A consultation booking's Checkout completed — the card is now authorized
  # (held). Record the PaymentIntent so accept/decline can capture/cancel it.
  # Matched ahead of the subscription clause by the `mode: "payment"` guard.
  defp dispatch_event(%{
         "type" => "checkout.session.completed",
         "data" => %{"object" => %{"mode" => "payment"} = session}
       }) do
    Mehungry.Professionals.mark_payment_authorized(session["id"], session["payment_intent"])
    :ok
  end

  # The client abandoned the consultation Checkout — release the pending booking.
  defp dispatch_event(%{
         "type" => "checkout.session.expired",
         "data" => %{"object" => %{"mode" => "payment"} = session}
       }) do
    Mehungry.Professionals.expire_payment_session(session["id"])
    :ok
  end

  defp dispatch_event(%{"type" => "payment_intent.canceled", "data" => %{"object" => pi}}) do
    Mehungry.Professionals.mark_payment_canceled_by_intent(pi["id"])
    :ok
  end

  defp dispatch_event(%{"type" => "payment_intent.payment_failed", "data" => %{"object" => pi}}) do
    reason = get_in(pi, ["last_payment_error", "message"])
    Mehungry.Professionals.mark_payment_failed(pi["id"], reason)
    :ok
  end

  defp dispatch_event(%{"type" => "charge.refunded", "data" => %{"object" => charge}}) do
    if charge["payment_intent"] do
      Mehungry.Professionals.mark_payment_refunded(
        charge["payment_intent"],
        charge["amount_refunded"],
        charge["amount"]
      )
    end

    :ok
  end

  # A client opened a dispute. We carry the dispute liability on destination
  # charges (even with on_behalf_of), so this is NOT log-only: alert + record it
  # on the ledger so support can respond with evidence before the deadline.
  defp dispatch_event(%{"type" => "charge.dispute.created", "data" => %{"object" => dispute}}) do
    Mehungry.Professionals.record_payment_dispute(dispute)

    Logger.error(
      "STRIPE DISPUTE opened on charge #{dispute["charge"]} (amount #{dispute["amount"]}, " <>
        "reason #{dispute["reason"]}) — platform liable, respond before the evidence deadline"
    )

    :ok
  end

  # The nutritionist disconnected their Stripe account from our platform — clear
  # the stored account id and mark them no longer chargeable.
  defp dispatch_event(%{
         "type" => "account.application.deauthorized",
         "account" => account_id
       })
       when is_binary(account_id) do
    Mehungry.Professionals.clear_stripe_connection(account_id)
    :ok
  end

  defp dispatch_event(%{"type" => "checkout.session.completed", "data" => %{"object" => session}}) do
    user_id = get_in(session, ["metadata", "user_id"]) |> parse_int()
    tier = get_in(session, ["metadata", "tier"])
    stripe_customer_id = session["customer"]
    stripe_subscription_id = session["subscription"]

    if user_id && stripe_subscription_id do
      period_end = fetch_subscription_period_end(stripe_subscription_id)
      activate_tier(tier, user_id, stripe_customer_id, stripe_subscription_id, period_end)
    end

    :ok
  end

  defp dispatch_event(%{
         "type" => "customer.subscription.updated",
         "data" => %{"object" => sub}
       }) do
    status = map_stripe_status(sub["status"])
    period_end = sub["current_period_end"] |> unix_to_naive()
    Subscriptions.update_subscription_status(sub["id"], status, period_end)
    :ok
  end

  defp dispatch_event(%{
         "type" => "customer.subscription.deleted",
         "data" => %{"object" => sub}
       }) do
    Subscriptions.cancel_subscription(sub["id"])
    Logger.info("Cancelled subscription #{sub["id"]}")
    :ok
  end

  # Accounts v2 account event (thin `v2.core.event` envelope — the capability/
  # requirements change is carried in `related_object.id`, not an inline object).
  # Fires as `v2.core.account[configuration.merchant].capability_status_updated`,
  # the recipient equivalent, and `v2.core.account[requirements].updated`. Any of
  # them can flip chargeability, so we re-fetch the account and recompute rather
  # than trust the (delivery-mode-dependent) inline `changes` hash.
  defp dispatch_event(%{
         "type" => "v2.core.account" <> _,
         "related_object" => %{"id" => account_id}
       })
       when is_binary(account_id) do
    Mehungry.Professionals.sync_stripe_account_status(account_id)
    :ok
  end

  # Accounts v1 account.updated — kept during the v1→v2 transition. Existing v1
  # connected accounts still fire this; v2-created accounts fire the clause above.
  defp dispatch_event(%{"type" => "account.updated", "data" => %{"object" => account}}) do
    account_id = account["id"]
    charges_enabled = account["charges_enabled"] == true

    if account_id do
      Mehungry.Professionals.set_stripe_charges_enabled(account_id, charges_enabled)
    end

    :ok
  end

  defp dispatch_event(%{"type" => type}) do
    Logger.debug("Unhandled Stripe event: #{type}")
    :ok
  end

  # Routes checkout completion to the correct tier activation based on the tier
  # stored in session metadata. Unknown/missing tiers fall back to the consumer
  # premium tier so pre-existing checkout links keep working.
  defp activate_tier("pro", user_id, customer_id, subscription_id, period_end) do
    Subscriptions.activate_nutritionist(user_id, customer_id, subscription_id, period_end)
    Logger.info("Activated Pro (nutritionist) for user #{user_id}")
  end

  defp activate_tier(_tier, user_id, customer_id, subscription_id, period_end) do
    Subscriptions.activate_pro(user_id, customer_id, subscription_id, period_end)
    Logger.info("Activated m3hungry_plus for user #{user_id}")
  end

  # ── Private: signature verification ──────────────────────────────────────────

  defp verify_signature(_body, _sig, ""), do: {:error, :webhook_secret_not_configured}
  defp verify_signature(_body, nil, _secret), do: {:error, :missing_signature}

  defp verify_signature(body, sig_header, secret) do
    parts =
      sig_header
      |> String.split(",")
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [k, v] -> Map.put(acc, k, v)
          _ -> acc
        end
      end)

    with timestamp when not is_nil(timestamp) <- Map.get(parts, "t"),
         expected_sig when not is_nil(expected_sig) <- Map.get(parts, "v1"),
         :ok <- check_timestamp_tolerance(timestamp),
         signed_payload = "#{timestamp}.#{body}",
         computed =
           :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(computed, expected_sig) do
      :ok
    else
      {:error, :timestamp_outside_tolerance} = error -> error
      _ -> {:error, :invalid_signature}
    end
  end

  # Stripe's default replay-protection window
  @timestamp_tolerance_seconds 300

  defp check_timestamp_tolerance(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} ->
        if abs(System.system_time(:second) - ts) <= @timestamp_tolerance_seconds do
          :ok
        else
          {:error, :timestamp_outside_tolerance}
        end

      _ ->
        {:error, :invalid_signature}
    end
  end

  # ── Private: HTTP ─────────────────────────────────────────────────────────────

  defp post(path, params, opts \\ []) do
    secret_key = config(:stripe_secret_key)

    if secret_key == "" do
      {:error, :stripe_not_configured}
    else
      # Drop nil values so optional params (e.g. customer_email) are simply absent.
      body = params |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> URI.encode_query()

      headers =
        [
          {"Authorization", "Bearer #{secret_key}"},
          {"Content-Type", "application/x-www-form-urlencoded"}
        ] ++ idempotency_header(opts[:idempotency_key])

      case HTTPoison.post(@stripe_api <> path, body, headers, recv_timeout: 15_000) do
        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
          Jason.decode(resp_body)

        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
          Logger.warning("Stripe #{path} returned #{code}: #{resp_body}")
          {:error, "Stripe error #{code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  # ── Private: HTTP (Accounts v2 core) ──────────────────────────────────────────
  #
  # The v2 core API takes a JSON body (not form-encoded) and requires the
  # preview `Stripe-Version` header. Path is relative to the /v2 base, e.g.
  # "/core/accounts".

  @stripe_v2_api "https://api.stripe.com/v2"

  defp post_v2(path, body) when is_map(body) do
    secret_key = config(:stripe_secret_key)

    if secret_key == "" do
      {:error, :stripe_not_configured}
    else
      case HTTPoison.post(@stripe_v2_api <> path, Jason.encode!(body), v2_headers(),
             recv_timeout: 15_000
           ) do
        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
          Jason.decode(resp_body)

        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
          Logger.warning("Stripe v2 POST #{path} returned #{code}: #{resp_body}")
          {:error, "Stripe error #{code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  defp get_v2(path) do
    secret_key = config(:stripe_secret_key)

    if secret_key == "" do
      {:error, :stripe_not_configured}
    else
      case HTTPoison.get(@stripe_v2_api <> path, v2_headers(), recv_timeout: 15_000) do
        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
          Jason.decode(resp_body)

        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
          Logger.warning("Stripe v2 GET #{path} returned #{code}: #{resp_body}")
          {:error, "Stripe error #{code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  defp v2_headers do
    [
      {"Authorization", "Bearer #{config(:stripe_secret_key)}"},
      {"Content-Type", "application/json"},
      {"Stripe-Version", config(:stripe_accounts_api_version)}
    ]
  end

  defp idempotency_header(nil), do: []
  defp idempotency_header(key), do: [{"Idempotency-Key", to_string(key)}]

  # The period-end fetcher can be overridden in tests via the
  # :stripe_period_end_fetcher app config key (a fun/1) so webhook dispatch can
  # be exercised without hitting the live Stripe API.
  defp fetch_subscription_period_end(subscription_id) do
    case Application.get_env(:mehungry, :stripe_period_end_fetcher) do
      fun when is_function(fun, 1) -> fun.(subscription_id)
      _ -> fetch_subscription_period_end_via_api(subscription_id)
    end
  end

  defp fetch_subscription_period_end_via_api(subscription_id) do
    secret_key = config(:stripe_secret_key)
    headers = [{"Authorization", "Bearer #{secret_key}"}]

    case HTTPoison.get("#{@stripe_api}/subscriptions/#{subscription_id}", headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"current_period_end" => ts}} -> unix_to_naive(ts)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ── Private: helpers ─────────────────────────────────────────────────────────

  defp config(key), do: Application.get_env(:mehungry, key, "")

  defp unix_to_naive(nil), do: nil

  defp unix_to_naive(ts) when is_integer(ts) do
    ts |> DateTime.from_unix!() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
  end

  defp map_stripe_status("active"), do: "active"
  defp map_stripe_status("trialing"), do: "trialing"
  defp map_stripe_status("past_due"), do: "past_due"
  defp map_stripe_status(_), do: "canceled"

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp parse_int(i) when is_integer(i), do: i
end
