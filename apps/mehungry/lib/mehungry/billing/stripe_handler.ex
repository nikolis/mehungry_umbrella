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
  Creates a Stripe Checkout Session for the Pro subscription.
  Returns {:ok, checkout_url} or {:error, reason}.
  """
  def create_checkout_session(user_id, user_email, price_id, success_url, cancel_url) do
    params = %{
      "mode" => "subscription",
      "customer_email" => user_email,
      "line_items[0][price]" => price_id,
      "line_items[0][quantity]" => "1",
      "success_url" => success_url,
      "cancel_url" => cancel_url,
      "metadata[user_id]" => to_string(user_id),
      "subscription_data[metadata][user_id]" => to_string(user_id)
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

  defp dispatch_event(%{"type" => "checkout.session.completed", "data" => %{"object" => session}}) do
    user_id = get_in(session, ["metadata", "user_id"]) |> parse_int()
    stripe_customer_id = session["customer"]
    stripe_subscription_id = session["subscription"]

    if user_id && stripe_subscription_id do
      period_end = fetch_subscription_period_end(stripe_subscription_id)
      Subscriptions.activate_pro(user_id, stripe_customer_id, stripe_subscription_id, period_end)
      Logger.info("Activated Pro for user #{user_id}")
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

  defp dispatch_event(%{"type" => type}) do
    Logger.debug("Unhandled Stripe event: #{type}")
    :ok
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
         signed_payload = "#{timestamp}.#{body}",
         computed = :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(computed, expected_sig) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  # ── Private: HTTP ─────────────────────────────────────────────────────────────

  defp post(path, params) do
    secret_key = config(:stripe_secret_key)

    if secret_key == "" do
      {:error, :stripe_not_configured}
    else
      body = URI.encode_query(params)

      headers = [
        {"Authorization", "Bearer #{secret_key}"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

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

  defp fetch_subscription_period_end(subscription_id) do
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
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)
  defp parse_int(i) when is_integer(i), do: i
end
