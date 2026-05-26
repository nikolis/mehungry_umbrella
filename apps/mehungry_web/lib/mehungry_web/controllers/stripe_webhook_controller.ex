defmodule MehungryWeb.StripeWebhookController do
  use MehungryWeb, :controller

  alias Mehungry.Billing.StripeHandler

  @doc """
  Receives Stripe webhook events. Stripe-Signature header is verified against
  STRIPE_WEBHOOK_SECRET before any processing.

  NOTE: Raw body caching must be active for signature verification to work.
  The endpoint reads the body once through Plug.Parsers — after that the raw
  bytes are gone. MehungryWeb.Plugs.CacheRawBody (registered in endpoint.ex)
  stashes the raw body in conn.assigns.raw_body before parsing.
  """
  def webhook(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case StripeHandler.handle_webhook(raw_body, signature) do
      :ok ->
        send_resp(conn, 200, "ok")

      {:error, :invalid_signature} ->
        send_resp(conn, 400, "invalid signature")

      {:error, :webhook_secret_not_configured} ->
        send_resp(conn, 500, "webhook not configured")

      {:error, reason} ->
        require Logger
        Logger.warning("Stripe webhook error: #{inspect(reason)}")
        send_resp(conn, 422, "unprocessable")
    end
  end
end
