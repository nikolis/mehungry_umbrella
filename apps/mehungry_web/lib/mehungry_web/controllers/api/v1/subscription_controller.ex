defmodule MehungryWeb.Api.V1.SubscriptionController do
  @moduledoc """
  Subscription info + Stripe checkout/portal URLs (spec §12). The mobile client
  opens the returned Stripe URL in an in-app browser; the existing
  `POST /webhooks/stripe` webhook activates the tier. Reuses
  `Billing.StripeHandler` (the same path the /upgrade LiveView uses).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Billing.StripeHandler
  alias Mehungry.Subscriptions

  action_fallback MehungryWeb.Api.V1.FallbackController

  def show(conn, _params) do
    user_id = conn.assigns.current_user.id
    subscription = Subscriptions.get_subscription(user_id)

    json(
      conn,
      data(%{
        tier: subscription.tier,
        plans: plans(),
        quota: quota(user_id)
      })
    )
  end

  def checkout(conn, params) do
    user = conn.assigns.current_user
    plan = params["plan"] || "m3hungry_plus"
    interval = params["interval"] || "monthly"

    with {:ok, price_id} <- price_id(plan, interval),
         base = MehungryWeb.Endpoint.url(),
         {:ok, url} <-
           StripeHandler.create_checkout_session(
             user.id,
             user.email,
             price_id,
             base <> "/upgrade?stripe_status=success&tier=#{plan}&interval=#{interval}",
             base <> "/upgrade?stripe_status=cancel",
             plan
           ) do
      json(conn, data(%{checkout_url: url}))
    else
      {:error, :stripe_not_configured} -> {:error, "Payment system is not configured yet."}
      {:error, :invalid_plan} -> {:error, :bad_request}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def portal(conn, _params) do
    subscription = Subscriptions.get_subscription(conn.assigns.current_user.id)

    case subscription.stripe_customer_id do
      nil ->
        {:error, :forbidden}

      customer_id ->
        base = MehungryWeb.Endpoint.url()

        with {:ok, url} <- StripeHandler.create_billing_portal_session(customer_id, base <> "/upgrade") do
          json(conn, data(%{portal_url: url}))
        else
          {:error, reason} when is_binary(reason) -> {:error, reason}
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp quota(user_id) do
    {rg_used, rg_limit} = Subscriptions.quota_status(user_id, "recipe_generation")
    {mp_used, mp_limit} = Subscriptions.quota_status(user_id, "meal_plan")

    %{
      recipe_generations: %{used: rg_used, limit: rg_limit},
      meal_plans: %{used: mp_used, limit: mp_limit}
    }
  end

  defp plans do
    [
      %{key: "free", name: "Free", price: nil, recipe_generations: 0, meal_plans: 0},
      %{
        key: "m3hungry_plus",
        name: "M3Hungry Plus",
        price: %{monthly: "€9.99"},
        recipe_generations: 15,
        meal_plans: 4
      },
      %{key: "pro", name: "Pro", price: %{monthly: "€19.99"}, recipe_generations: 30, meal_plans: 10}
    ]
  end

  defp price_id("m3hungry_plus", "yearly"),
    do: env(:stripe_pro_yearly_price_id)

  defp price_id("m3hungry_plus", _monthly), do: env(:stripe_pro_price_id)
  defp price_id("pro", "yearly"), do: env(:stripe_nutritionist_yearly_price_id)
  defp price_id("pro", _monthly), do: env(:stripe_nutritionist_price_id)
  defp price_id(_plan, _interval), do: {:error, :invalid_plan}

  defp env(key) do
    case Application.get_env(:mehungry, key, "") do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :stripe_not_configured}
    end
  end
end
