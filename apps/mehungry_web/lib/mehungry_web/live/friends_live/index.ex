defmodule MehungryWeb.FriendsLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Friends

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Friends")
     |> assign(:invite_email, "")
     |> assign(:invite_message, "")
     |> assign(:invite_error, nil)
     |> load_friends()}
  end

  defp load_friends(socket) do
    user_id = socket.assigns.current_user.id

    socket
    |> assign(:friends, Friends.list_friends(user_id))
    |> assign(:incoming, Friends.list_pending_requests_for(user_id))
    |> assign(:sent, Friends.list_sent_requests(user_id))
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("send_friend_request", %{"email" => email, "message" => message}, socket) do
    requester_id = socket.assigns.current_user.id

    case Friends.send_friend_request_by_email(requester_id, String.trim(email), message) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> assign(:invite_email, "")
         |> assign(:invite_message, "")
         |> assign(:invite_error, nil)
         |> load_friends()
         |> put_flash(:info, "Friend request sent to #{email}.")}

      {:error, reason} ->
        {:noreply, assign(socket, :invite_error, request_error_message(reason))}
    end
  end

  @impl true
  def handle_event("accept_friend_request", %{"id" => id}, socket) do
    case Friends.accept_friend_request(String.to_integer(id), socket.assigns.current_user.id) do
      {:ok, _friendship} ->
        {:noreply, socket |> load_friends() |> put_flash(:info, "You are now friends!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not accept request.")}
    end
  end

  @impl true
  def handle_event("decline_friend_request", %{"id" => id}, socket) do
    case Friends.decline_friend_request(String.to_integer(id), socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply, socket |> load_friends() |> put_flash(:info, "Request declined.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not decline request.")}
    end
  end

  @impl true
  def handle_event("cancel_friend_request", %{"id" => id}, socket) do
    case Friends.cancel_friend_request(String.to_integer(id), socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply, socket |> load_friends() |> put_flash(:info, "Request cancelled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel request.")}
    end
  end

  @impl true
  def handle_event("unfriend", %{"id" => id}, socket) do
    case Friends.unfriend(socket.assigns.current_user.id, String.to_integer(id)) do
      {:ok, _} ->
        {:noreply, socket |> load_friends() |> put_flash(:info, "Friend removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove friend.")}
    end
  end

  defp request_error_message(:user_not_found), do: "No user found with that email address."
  defp request_error_message(:self), do: "You can't send a friend request to yourself."
  defp request_error_message(:already_friends), do: "You are already friends with this user."

  defp request_error_message(:already_requested),
    do: "You already have a pending request to this user."

  defp request_error_message(_), do: "Could not send request. Please try again."

  # ── View ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-display font-medium text-parchment mb-6">Friends</h1>

      <!-- Add-friend form -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-2xl p-6 mb-8">
        <h2 class="text-parchment font-display text-lg font-medium mb-4">Add a friend</h2>
        <form phx-submit="send_friend_request" class="space-y-3">
          <div>
            <label class="block text-sm text-parchment-dim mb-1">Friend's email address</label>
            <input
              type="email"
              name="email"
              value={@invite_email}
              required
              placeholder="friend@example.com"
              class="w-full bg-black/20 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm placeholder:text-parchment-dim/60 focus:outline-none focus:border-paprika"
            />
          </div>
          <div>
            <label class="block text-sm text-parchment-dim mb-1">Personal message (optional)</label>
            <textarea
              name="message"
              rows="2"
              placeholder="Hey! Let's share ingredients."
              class="w-full bg-black/20 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm placeholder:text-parchment-dim/60 focus:outline-none focus:border-paprika"
            >{@invite_message}</textarea>
          </div>
          <%= if @invite_error do %>
            <p class="text-red-400 text-sm">{@invite_error}</p>
          <% end %>
          <button
            type="submit"
            class="bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm py-2.5 px-5 rounded-lg transition-colors"
          >
            Send Request
          </button>
        </form>
      </div>

      <!-- Incoming requests -->
      <%= if not Enum.empty?(@incoming) do %>
        <h2 class="text-parchment font-display text-lg font-medium mb-3">Requests received</h2>
        <div class="space-y-4 mb-8">
          <%= for req <- @incoming do %>
            <% user = req.requester %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-2xl p-5">
              <div class="flex items-start gap-3 mb-4">
                {avatar(assigns |> Map.put(:user, user))}
                <div class="flex-1">
                  <p class="text-parchment font-medium">{display_name(user)}</p>
                  <%= if req.message do %>
                    <p class="text-parchment-dim text-sm mt-2 bg-black/20 rounded-lg px-3 py-2 italic">
                      "{req.message}"
                    </p>
                  <% end %>
                </div>
              </div>
              <div class="flex gap-3">
                <button
                  phx-click="accept_friend_request"
                  phx-value-id={req.id}
                  class="flex-1 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition-colors"
                >
                  Accept
                </button>
                <button
                  phx-click="decline_friend_request"
                  phx-value-id={req.id}
                  class="flex-1 py-2 rounded-lg bg-ink-panel2 hover:bg-ink-panel2/70 text-parchment-dim hover:text-parchment text-sm font-medium transition-colors"
                >
                  Decline
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Sent requests -->
      <%= if not Enum.empty?(@sent) do %>
        <h2 class="text-parchment font-display text-lg font-medium mb-3">Requests sent</h2>
        <div class="space-y-3 mb-8">
          <%= for req <- @sent do %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-2xl p-4 flex items-center justify-between">
              <div>
                <p class="text-parchment text-sm font-medium">{display_name(req.recipient)}</p>
                <span class="text-xs px-2 py-0.5 rounded-full font-medium bg-yellow-500/15 text-yellow-400/90">
                  Pending
                </span>
              </div>
              <button
                phx-click="cancel_friend_request"
                phx-value-id={req.id}
                data-confirm="Cancel this request?"
                class="text-xs text-red-400 hover:text-red-300"
              >
                Cancel
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Friends -->
      <h2 class="text-parchment font-display text-lg font-medium mb-3">Your Friends</h2>
      <%= if Enum.empty?(@friends) do %>
        <p class="text-parchment-dim text-sm">You don't have any friends yet.</p>
      <% else %>
        <div class="space-y-3">
          <%= for friend <- @friends do %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-2xl p-4 flex items-center justify-between">
              <div class="flex items-center gap-3">
                {avatar(assigns |> Map.put(:user, friend))}
                <p class="text-parchment text-sm font-medium">{display_name(friend)}</p>
              </div>
              <button
                phx-click="unfriend"
                phx-value-id={friend.id}
                data-confirm="Remove this friend?"
                class="text-xs text-red-400 hover:text-red-300"
              >
                Remove
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp avatar(assigns) do
    ~H"""
    <%= if @user.profile_pic do %>
      <img src={@user.profile_pic} class="w-10 h-10 rounded-full object-cover shrink-0" />
    <% else %>
      <div class="w-10 h-10 rounded-full bg-ink-panel2 flex items-center justify-center text-parchment font-bold text-sm shrink-0">
        {String.first(display_name(@user))}
      </div>
    <% end %>
    """
  end

  defp display_name(user), do: user.name || user.email || "?"
end
