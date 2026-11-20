defmodule MehungryWeb.ShoppingBasketLive.Invitation do
  @moduledoc """
  Landing page for a shared-shopping-list invitation link
  (`/basket/invitations/:token`). The route requires a signed-in user, so
  someone without an account is sent to log in / sign up first and returned
  here. Before accepting, the invitee sees only who invited them and the list's
  title. See `docs/features/shared_basket.md`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Inventory
  alias MehungryWeb.BasketSharing

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    preview =
      case Inventory.preview_invitation(token) do
        {:ok, preview} -> preview
        {:error, _} -> nil
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Shopping list invitation"))
     |> assign(:token, token)
     |> assign(:preview, preview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="basket-page min-h-screen bg-ink text-parchment" id="basket-invitation">
      <div class="max-w-md mx-auto px-4 py-16">
        <div class="bg-ink-panel rounded-xl border border-ink-panel2 p-6 text-center">
          <%= if @preview do %>
            <h1 class="text-2xl font-display font-medium text-parchment">
              {gettext("Share a shopping list")}
            </h1>
            <p class="text-parchment-dim mt-3">
              {gettext("%{name} invited you to share “%{title}”",
                name: @preview.inviter_name || gettext("Someone"),
                title: @preview.basket_title
              )}
            </p>
            <p class="text-parchment-dim text-sm mt-2">
              {gettext(
                "Everyone on the list sees the same items and can add to it and tick things off."
              )}
            </p>
            <div class="mt-6 flex flex-col gap-2">
              <button
                phx-click="accept"
                id="accept-invitation"
                class="w-full bg-paprika hover:bg-paprika-soft text-ink font-bold py-2 rounded-lg transition"
              >
                {gettext("Join the list")}
              </button>
              <.link
                navigate={~p"/basket"}
                class="w-full text-parchment-dim hover:text-parchment py-2 rounded-lg transition"
              >
                {gettext("Not now")}
              </.link>
            </div>
          <% else %>
            <h1 class="text-2xl font-display font-medium text-parchment">
              {gettext("This invitation is no longer valid.")}
            </h1>
            <p class="text-parchment-dim mt-3">
              {gettext("It may have been used already, revoked, or expired. Ask for a new one.")}
            </p>
            <.link
              navigate={~p"/basket"}
              class="mt-6 inline-block text-paprika-soft hover:text-paprika transition"
            >
              {gettext("Go to my shopping lists")}
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("accept", _params, socket) do
    case Inventory.accept_invitation_by_token(socket.assigns.current_user, socket.assigns.token) do
      {:ok, basket} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("You joined “%{title}”", title: basket.title))
         |> push_navigate(to: ~p"/basket?basket_id=#{basket.id}")}

      {:error, :invalid} ->
        {:noreply, assign(socket, :preview, nil)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, BasketSharing.error_message(reason))}
    end
  end
end
