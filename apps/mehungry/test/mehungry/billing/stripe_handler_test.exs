defmodule Mehungry.Billing.StripeHandlerTest do
  use Mehungry.DataCase, async: false

  alias Mehungry.Billing.StripeHandler
  alias Mehungry.Subscriptions
  alias Mehungry.AccountsFixtures

  @webhook_secret "whsec_test_secret"
  # Fixed value returned by the injected period-end fetcher so dispatch never
  # touches the live Stripe API.
  @period_end ~N[2026-08-01 00:00:00]

  setup do
    prev_secret = Application.get_env(:mehungry, :stripe_webhook_secret)
    prev_fetcher = Application.get_env(:mehungry, :stripe_period_end_fetcher)

    Application.put_env(:mehungry, :stripe_webhook_secret, @webhook_secret)
    Application.put_env(:mehungry, :stripe_period_end_fetcher, fn _sub_id -> @period_end end)

    on_exit(fn ->
      restore(:stripe_webhook_secret, prev_secret)
      restore(:stripe_period_end_fetcher, prev_fetcher)
    end)

    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  defp restore(key, nil), do: Application.delete_env(:mehungry, key)
  defp restore(key, value), do: Application.put_env(:mehungry, key, value)

  # Builds the Stripe-Signature header for a raw JSON body using the same
  # HMAC-SHA256 scheme the handler verifies against.
  defp sign(body, secret \\ @webhook_secret) do
    sign_at(body, Integer.to_string(System.system_time(:second)), secret)
  end

  defp sign_at(body, ts, secret \\ @webhook_secret) do
    sig = :crypto.mac(:hmac, :sha256, secret, "#{ts}.#{body}") |> Base.encode16(case: :lower)
    "t=#{ts},v1=#{sig}"
  end

  defp checkout_completed_body(user_id, metadata) do
    Jason.encode!(%{
      "type" => "checkout.session.completed",
      "data" => %{
        "object" => %{
          "customer" => "cus_#{user_id}",
          "subscription" => "sub_#{user_id}",
          "metadata" => Map.merge(%{"user_id" => to_string(user_id)}, metadata)
        }
      }
    })
  end

  describe "checkout.session.completed tier routing" do
    test "tier metadata \"pro\" activates the nutritionist tier", %{user: user} do
      body = checkout_completed_body(user.id, %{"tier" => "pro"})
      assert :ok = StripeHandler.handle_webhook(body, sign(body))

      sub = Subscriptions.get_subscription(user.id)
      assert sub.tier == "pro"
      assert sub.status == "active"
      assert sub.stripe_customer_id == "cus_#{user.id}"
      assert sub.stripe_subscription_id == "sub_#{user.id}"
      assert sub.period_end == @period_end
    end

    test "tier metadata \"m3hungry_plus\" activates the consumer tier", %{user: user} do
      body = checkout_completed_body(user.id, %{"tier" => "m3hungry_plus"})
      assert :ok = StripeHandler.handle_webhook(body, sign(body))

      assert Subscriptions.get_subscription(user.id).tier == "m3hungry_plus"
    end

    test "missing tier metadata defaults to the consumer tier", %{user: user} do
      body = checkout_completed_body(user.id, %{})
      assert :ok = StripeHandler.handle_webhook(body, sign(body))

      assert Subscriptions.get_subscription(user.id).tier == "m3hungry_plus"
    end
  end

  describe "signature verification" do
    test "rejects a tampered signature", %{user: user} do
      body = checkout_completed_body(user.id, %{"tier" => "pro"})
      bad_sig = sign(body, "whsec_wrong_secret")

      assert {:error, :invalid_signature} = StripeHandler.handle_webhook(body, bad_sig)
      # No subscription should have been created.
      assert Subscriptions.get_subscription(user.id).tier == "free"
    end

    test "rejects a missing signature header", %{user: user} do
      body = checkout_completed_body(user.id, %{"tier" => "pro"})
      assert {:error, :missing_signature} = StripeHandler.handle_webhook(body, nil)
    end

    test "rejects a replayed event with a stale timestamp", %{user: user} do
      body = checkout_completed_body(user.id, %{"tier" => "pro"})
      stale_ts = Integer.to_string(System.system_time(:second) - 600)

      assert {:error, :timestamp_outside_tolerance} =
               StripeHandler.handle_webhook(body, sign_at(body, stale_ts))

      assert Subscriptions.get_subscription(user.id).tier == "free"
    end

    test "rejects a non-numeric timestamp", %{user: user} do
      body = checkout_completed_body(user.id, %{"tier" => "pro"})

      assert {:error, :invalid_signature} =
               StripeHandler.handle_webhook(body, sign_at(body, "garbage"))
    end
  end

  describe "malformed metadata" do
    test "non-numeric metadata.user_id is ignored instead of crashing", %{user: user} do
      body =
        Jason.encode!(%{
          "type" => "checkout.session.completed",
          "data" => %{
            "object" => %{
              "customer" => "cus_x",
              "subscription" => "sub_x",
              "metadata" => %{"user_id" => "not-a-number", "tier" => "pro"}
            }
          }
        })

      assert :ok = StripeHandler.handle_webhook(body, sign(body))
      assert Subscriptions.get_subscription(user.id).tier == "free"
    end
  end

  describe "subscription lifecycle events" do
    setup %{user: user} do
      {:ok, _sub} =
        Subscriptions.activate_nutritionist(user.id, "cus_x", "sub_lifecycle", @period_end)

      :ok
    end

    test "customer.subscription.updated maps the status", %{user: user} do
      body =
        Jason.encode!(%{
          "type" => "customer.subscription.updated",
          "data" => %{"object" => %{"id" => "sub_lifecycle", "status" => "past_due"}}
        })

      assert :ok = StripeHandler.handle_webhook(body, sign(body))
      assert Subscriptions.get_subscription(user.id).status == "past_due"
    end

    test "customer.subscription.deleted downgrades to free/canceled", %{user: user} do
      body =
        Jason.encode!(%{
          "type" => "customer.subscription.deleted",
          "data" => %{"object" => %{"id" => "sub_lifecycle"}}
        })

      assert :ok = StripeHandler.handle_webhook(body, sign(body))

      sub = Subscriptions.get_subscription(user.id)
      assert sub.tier == "free"
      assert sub.status == "canceled"
    end
  end
end
