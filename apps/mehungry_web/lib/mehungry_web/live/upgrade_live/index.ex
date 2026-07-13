defmodule MehungryWeb.UpgradeLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Subscriptions
  alias Mehungry.Billing.StripeHandler

  use MehungryWeb.Presence, :user_tracking

  @monthly_price_display "€9.99"
  @yearly_price_display "€99"

  @nutritionist_monthly_price_display "€59.00"
  @nutritionist_yearly_price_display "€599"

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    subscription = Subscriptions.get_subscription(user.id)

    {recipe_used, recipe_limit} = Subscriptions.quota_status(user.id, "recipe_generation")
    {plan_used, plan_limit} = Subscriptions.quota_status(user.id, "meal_plan")

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:subscription, subscription)
     |> assign(:recipe_used, recipe_used)
     |> assign(:recipe_limit, recipe_limit)
     |> assign(search_query: "")
     |> assign(search_results: [])
     |> assign(:plan_used, plan_used)
     |> assign(:plan_limit, plan_limit)
     |> assign(:stripe_status, nil)
     |> assign(:page_title, "Upgrade to Mehungry Plus")}
  end

  @impl true
  def handle_params(%{"stripe_status" => "success"}, _uri, socket) do
    subscription = Subscriptions.get_subscription(socket.assigns.user.id)
    {:noreply, socket |> assign(:stripe_status, :success) |> assign(:subscription, subscription)}
  end

  def handle_params(%{"stripe_status" => "cancel"}, _uri, socket) do
    {:noreply, assign(socket, :stripe_status, :cancel)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("subscribe", %{"interval" => interval}, socket) do
    user = socket.assigns.user
    price_id = get_price_id(interval)
    base_url = MehungryWeb.Endpoint.url()

    success_url = base_url <> "/upgrade?stripe_status=success"
    cancel_url = base_url <> "/upgrade?stripe_status=cancel"

    case StripeHandler.create_checkout_session(
           user.id,
           user.email,
           price_id,
           success_url,
           cancel_url,
           "m3hungry_plus"
         ) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, :stripe_not_configured} ->
        {:noreply, put_flash(socket, :error, "Payment system is not configured yet.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start checkout: #{reason}")}
    end
  end

  def handle_event("subscribe_nutritionist", %{"interval" => interval}, socket) do
    user = socket.assigns.user
    price_id = get_nutritionist_price_id(interval)
    base_url = MehungryWeb.Endpoint.url()

    success_url = base_url <> "/upgrade?stripe_status=success"
    cancel_url = base_url <> "/upgrade?stripe_status=cancel"

    case StripeHandler.create_checkout_session(
           user.id,
           user.email,
           price_id,
           success_url,
           cancel_url,
           "pro"
         ) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, :stripe_not_configured} ->
        {:noreply, put_flash(socket, :error, "Payment system is not configured yet.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start checkout: #{reason}")}
    end
  end

  def handle_event("manage_subscription", _params, socket) do
    sub = socket.assigns.subscription
    base_url = MehungryWeb.Endpoint.url()

    case StripeHandler.create_billing_portal_session(
           sub.stripe_customer_id,
           base_url <> "/upgrade"
         ) do
      {:ok, portal_url} ->
        {:noreply, redirect(socket, external: portal_url)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not open billing portal: #{reason}")}
    end
  end

  attr :text, :string, required: true
  attr :included, :boolean, required: true

  def feature_row(assigns) do
    ~H"""
    <li class="flex items-center gap-2.5">
      <%= if @included do %>
        <svg
          class="w-4 h-4 text-green-400 flex-shrink-0"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" />
        </svg>
        <span class="text-slate-300">{@text}</span>
      <% else %>
        <svg
          class="w-4 h-4 text-slate-600 flex-shrink-0"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M6 18L18 6M6 6l12 12"
          />
        </svg>
        <span class="text-slate-600">{@text}</span>
      <% end %>
    </li>
    """
  end

  defp get_price_id("monthly") do
    Application.get_env(:mehungry, :stripe_pro_price_id, "")
  end

  defp get_price_id("yearly") do
    Application.get_env(:mehungry, :stripe_pro_yearly_price_id, "")
  end

  defp get_nutritionist_price_id("monthly") do
    Application.get_env(:mehungry, :stripe_nutritionist_price_id, "")
  end

  defp get_nutritionist_price_id("yearly") do
    Application.get_env(:mehungry, :stripe_nutritionist_yearly_price_id, "")
  end

  def monthly_price, do: @monthly_price_display
  def yearly_price, do: @yearly_price_display
  def nutritionist_monthly_price, do: @nutritionist_monthly_price_display
  def nutritionist_yearly_price, do: @nutritionist_yearly_price_display
end
