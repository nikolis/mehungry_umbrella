defmodule MehungryWeb.ProfileLive.Show do
  use MehungryWeb, :live_component

  alias Mehungry.Friends
  alias Mehungry.Subscriptions

  @impl true
  # Targeted refresh from the parent's "add_friend" handler — just swap the
  # button state, no re-fetch of the rest of the profile.
  def update(%{friend_status: status}, socket) do
    {:ok, assign(socket, :friend_status, status)}
  end

  def update(%{user_profile: user_profile, user_follows: user_follows} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user_profile, user_profile)
     |> assign(:user_follows, user_follows)
     |> assign_friend_status()}
  end

  # Relationship between the signed-in user and the profile being viewed, used to
  # decide whether to offer the "Add Friend" button on someone else's profile.
  defp assign_friend_status(socket) do
    current_user = socket.assigns[:current_user]
    user = socket.assigns[:user]

    status =
      if is_nil(current_user) or is_nil(user) do
        :none
      else
        Friends.relationship_status(current_user.id, user.id)
      end

    assign(socket, :friend_status, status)
  end

  # Profile-local hero. Replaces the shared `user_details_card` for this page so
  # the identity/stats block, account controls, and relationship actions all live
  # in one place with a clear hierarchy. `mode` is :index (your own profile) or
  # :show (someone else's); `compact` collapses the hero to identity-only when a
  # manage panel (edit / connections / ingredients) is open underneath.
  attr :mode, :atom, required: true, values: [:index, :show]
  attr :compact, :boolean, default: false
  attr :user, :map, required: true
  attr :user_profile, :map, required: true
  attr :current_user, :map, default: nil
  attr :user_follows, :list, default: []
  attr :friend_status, :atom, default: :none
  attr :myself, :any, default: nil
  attr :socket, :any, required: true

  def profile_hero(assigns) do
    assigns =
      assigns
      |> assign(:name, display_name(assigns.user, assigns.user_profile, assigns.mode))
      |> assign(
        :viewing_other,
        assigns.current_user && assigns.user && assigns.current_user.id != assigns.user.id
      )

    ~H"""
    <div class="flex flex-col items-center gap-5 text-center sm:flex-row sm:gap-6 sm:text-left">
      <.link
        patch={~p"/profile/#{@user.id}"}
        class="shrink-0 rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika"
      >
        <%= if @user.profile_pic do %>
          <img
            src={@user.profile_pic}
            alt={@name}
            class="h-24 w-24 sm:h-28 sm:w-28 shrink-0 rounded-full object-cover ring-1 ring-ink-panel2"
          />
        <% else %>
          <div class="flex h-24 w-24 sm:h-28 sm:w-28 shrink-0 items-center justify-center rounded-full bg-ink-panel2 ring-1 ring-ink-panel2">
            <span class="font-display text-3xl font-medium text-basil">
              {avatar_initial(@name)}
            </span>
          </div>
        <% end %>
      </.link>

      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center justify-center gap-x-3 gap-y-1 sm:justify-start">
          <h1 class="font-display text-2xl sm:text-3xl font-medium text-parchment break-words">
            {@name}
          </h1>
          <.subscription_badge tier={Subscriptions.get_subscription(@user.id).tier} />
          <%= if @mode == :index do %>
            <div class="py-1">
              <.share_button user={@user} socket={@socket} />
            </div>
          <% end %>
        </div>

        <p :if={@mode == :index} class="mt-0.5 text-sm text-parchment-dim">{@user.email}</p>
        <p :if={present?(@user_profile.intro)} class="mt-1 max-w-prose text-sm text-parchment-dim">
          {@user_profile.intro}
        </p>

        <div
          :if={not @compact}
          class="mt-4 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 sm:justify-start"
        >
          <%= if @mode == :index do %>
            <.link patch={~p"/profile?#{[tab: "created"]}"} class="flex flex-col items-center leading-tight sm:items-start rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika">
              <.stat_number value={count_user_created_recipes(@user.id)} />
              <span class="text-sm text-parchment-dim">Posted</span>
            </.link>
            <.link navigate={~p"/friends"} class="flex flex-col items-center leading-tight sm:items-start rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika">
              <.stat_number value={count_user_followers(@user.id)} />
              <span class="text-sm text-parchment-dim">Followers</span>
            </.link>
            <.link navigate={~p"/friends"} class="flex flex-col items-center leading-tight sm:items-start rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika">
              <.stat_number value={count_user_following(@user.id)} />
              <span class="text-sm text-parchment-dim">Following</span>
            </.link>
          <% else %>
            <span class="flex flex-col items-center leading-tight sm:items-start rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika">
              <.stat_number value={count_user_created_recipes(@user.id)} />
              <span class="text-sm text-parchment-dim">Posted</span>
            </span>
            <span class="flex flex-col items-center leading-tight sm:items-start rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika">
              <.stat_number value={count_user_followers(@user.id)} />
              <span class="text-sm text-parchment-dim">Followers</span>
            </span>
            <span class="flex flex-col items-center leading-tight sm:items-start rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika">
              <.stat_number value={count_user_following(@user.id)} />
              <span class="text-sm text-parchment-dim">Following</span>
            </span>
          <% end %>
        </div>

        <%!-- Relationship actions on someone else's profile: one paprika primary
              (Add Friend / Respond), with Follow kept as a quiet companion. --%>
        <div :if={@mode == :show and @viewing_other} class="mt-4 flex flex-wrap items-center justify-center gap-3 sm:justify-start">
          <%= case @friend_status do %>
            <% :friends -> %>
              <span class="inline-flex items-center gap-1.5 py-2 px-5 rounded-full bg-ink-panel2 text-parchment-dim text-sm font-medium">
                <.icon name="hero-check" class="w-4 h-4 flex-none" /> Friends
              </span>
            <% :request_sent -> %>
              <span class="inline-flex items-center gap-1.5 py-2 px-5 rounded-full bg-ink-panel2 text-parchment-dim text-sm font-medium">
                <.icon name="hero-clock" class="w-4 h-4 flex-none" /> Request sent
              </span>
            <% :request_received -> %>
              <.link
                navigate={~p"/friends"}
                class="inline-flex items-center gap-1.5 py-2 px-5 rounded-full bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition-colors motion-reduce:transition-none"
              >
                <.icon name="hero-user-plus" class="w-4 h-4 flex-none" /> Respond to request
              </.link>
            <% _ -> %>
              <button
                type="button"
                phx-click="add_friend"
                phx-value-id={@user.id}
                class="inline-flex items-center gap-1.5 py-2 px-5 rounded-full bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition-colors motion-reduce:transition-none"
              >
                <.icon name="hero-user-plus" class="w-4 h-4 flex-none" /> Add Friend
              </button>
          <% end %>

          <button
            type="button"
            id={"toggle_user_follow#{@user.id}"}
            phx-click="save_user_follow"
            phx-value-follow_id={@user.id}
            class="inline-flex items-center gap-1.5 py-2 px-5 rounded-full border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm font-medium transition-colors motion-reduce:transition-none"
          >
            {if @user.id in @user_follows, do: "Following", else: "Follow"}
          </button>
        </div>
      </div>
    </div>

    <%!-- Account zone — your own profile, content mode only. One paprika primary
          (Upgrade); everything else is a quiet ghost control grouped by purpose. --%>
    <div :if={@mode == :index and not @compact} class="mt-6 pt-5 border-t border-ink-panel2">
      <% subscription = Subscriptions.get_subscription(@user.id) %>
      <div class="flex flex-col items-center gap-4">
        <%= if subscription.tier == "free" do %>
          <.link href={~p"/upgrade"}>
            <button
              type="button"
              class="inline-flex items-center gap-2 py-2.5 px-6 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition-colors motion-reduce:transition-none"
            >
              <.icon name="hero-sparkles" class="w-5 h-5 flex-none" /> Upgrade to Mehungry Plus
            </button>
          </.link>
        <% else %>
          <.link href={~p"/upgrade"} class="flex flex-col items-center gap-1.5">
            <.subscription_badge tier={subscription.tier} />
            <span class="text-sm text-parchment-dim hover:text-parchment transition-colors">
              {if subscription.status == "active",
                do: "Your subscription is active — manage it",
                else: String.capitalize(subscription.status) <> " subscription — manage it"}
            </span>
          </.link>
        <% end %>

        <div class="flex flex-wrap items-center justify-center gap-x-5 gap-y-2">
          <.link patch={~p"/profile?#{[tab: "edit_profile"]}"} phx-click={JS.push_focus()} class="inline-flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition-colors motion-reduce:transition-none">
            <.icon name="hero-pencil-square" class="w-4 h-4 flex-none" /> Edit profile
          </.link>
          <.link patch={~p"/profile?#{[tab: "connected_accounts"]}"} phx-click={JS.push_focus()} class="inline-flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition-colors motion-reduce:transition-none">
            <.icon name="hero-link" class="w-4 h-4 flex-none" /> Connections
          </.link>
          <.link patch={~p"/profile?#{[tab: "ingredients"]}"} phx-click={JS.push_focus()} class="inline-flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition-colors motion-reduce:transition-none">
            <.icon name="hero-beaker" class="w-4 h-4 flex-none" /> My ingredients
          </.link>
          <%= if @current_user && @current_user.email == "nikolisgal@gmail.com" do %>
            <.link patch={~p"/professional/activeusers"} phx-click={JS.push_focus()} class="inline-flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition-colors motion-reduce:transition-none">
              <.icon name="hero-wrench-screwdriver" class="w-4 h-4 flex-none" /> Professional
            </.link>
            <.link patch={~p"/professional/analytics"} phx-click={JS.push_focus()} class="inline-flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition-colors motion-reduce:transition-none">
              <.icon name="hero-chart-bar" class="w-4 h-4 flex-none" /> Analytics
            </.link>
          <% end %>
        </div>

        <div class="inline-flex items-center gap-1 rounded-full bg-ink-panel2 p-1">
          <a
            href="/users/language/en"
            class={"px-5 py-1.5 rounded-full text-sm transition-colors motion-reduce:transition-none #{if (@user_profile.language_preference || "en") == "en", do: "bg-ink/60 text-parchment font-semibold", else: "text-parchment-dim hover:text-parchment"}"}
          >
            EN
          </a>
          <a
            href="/users/language/el"
            class={"px-5 py-1.5 rounded-full text-sm transition-colors motion-reduce:transition-none #{if (@user_profile.language_preference || "en") == "el", do: "bg-ink/60 text-parchment font-semibold", else: "text-parchment-dim hover:text-parchment"}"}
          >
            ΕΛ — Ελληνικά
          </a>
        </div>

        <div class="flex items-center justify-center gap-5 text-xs">
          <.link patch={~p"/users/log_out"} phx-click={JS.push_focus()} class="inline-flex items-center gap-1.5 text-parchment-dim hover:text-parchment transition-colors motion-reduce:transition-none">
            <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4 flex-none" /> Log out
          </.link>
          <.link
            patch={~p"/users/delete"}
            phx-click={JS.push_focus()}
            data-confirm="Are you sure you want to completely erase your account?"
            class="inline-flex items-center gap-1.5 text-red-500/70 hover:text-red-400 transition-colors motion-reduce:transition-none"
          >
            <.icon name="hero-trash" class="w-4 h-4 flex-none" /> Delete account
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :value, :integer, required: true

  defp stat_number(assigns) do
    ~H"""
    <span class="text-xl font-bold text-basil [font-variant-numeric:tabular-nums]">{@value}</span>
    """
  end

  # Public identity shown as the heading. Prefer the chosen alias, then the real
  # name; fall back to the email only on your own profile, never on a public one.
  defp display_name(user, user_profile, mode) do
    cond do
      user_profile && present?(user_profile.alias) -> user_profile.alias
      user && present?(user.name) -> user.name
      mode == :index && user && present?(user.email) -> user.email
      true -> "Mehungry cook"
    end
  end

  defp avatar_initial(name) do
    (name |> String.trim() |> String.first() || "M") |> String.upcase()
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
