defmodule Mehungry.Billing.StripePaymentClientStub do
  @moduledoc """
  Test stand-in for the money-moving `Mehungry.Billing.StripeHandler` Connect
  calls, wired via the `:stripe_payment_client` config key. Lets
  `Professionals` payment-lifecycle tests capture/cancel/refund without hitting
  Stripe.

  Each call sends `{:stripe, name, args}` to the process registered in the
  `:stripe_stub_pid` app env (default: the current process) so tests can assert
  what was invoked, and returns a canned success by default. Override any result
  with a `fn args -> result end` under `:stripe_stub_<name>`.
  """

  def create_consultation_checkout(opts) do
    dispatch(:create_consultation_checkout, opts, fn ->
      {:ok, %{url: "https://checkout.stripe.test/session", session_id: "cs_test_123"}}
    end)
  end

  def capture_payment_intent(pi_id) do
    dispatch(:capture_payment_intent, pi_id, fn -> {:ok, %{charge_id: "ch_test_#{pi_id}"}} end)
  end

  def cancel_payment_intent(pi_id) do
    dispatch(:cancel_payment_intent, pi_id, fn -> :ok end)
  end

  def refund_payment(pi_id, opts \\ []) do
    dispatch(:refund_payment, {pi_id, opts}, fn -> {:ok, %{refund_id: "re_test_#{pi_id}"}} end)
  end

  def create_login_link(account_id) do
    dispatch(:create_login_link, account_id, fn ->
      {:ok, "https://connect.stripe.test/express/#{account_id}"}
    end)
  end

  def get_connect_account(account_id) do
    dispatch(:get_connect_account, account_id, fn ->
      {:ok, %{charges_enabled: true, payouts_enabled: true, details_submitted: true}}
    end)
  end

  defp dispatch(name, args, default) do
    if pid = Application.get_env(:mehungry, :stripe_stub_pid),
      do: send(pid, {:stripe, name, args})

    case Application.get_env(:mehungry, :"stripe_stub_#{name}") do
      fun when is_function(fun, 1) -> fun.(args)
      _ -> default.()
    end
  end
end
