defmodule MehungryWeb.ProfessionalLive.User do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Food
  alias Mehungry.Posts
  alias Mehungry.Subscriptions

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    user = Accounts.get_user!(id)

    stats = %{
      recipes_created: Food.count_user_created_recipes(user.id),
      recipes_liked: Food.count_user_liked_recipes(user.id),
      recipes_saved: Accounts.count_user_saved_recipes(user.id),
      comments: Posts.count_user_comments(user.id),
      posts: Posts.count_user_posts(user.id),
      followers: Accounts.count_user_followers(user.id),
      following: Accounts.count_user_following(user.id)
    }

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:user, user)
     |> assign(:subscription, Subscriptions.get_subscription(user.id))
     |> assign(:stats, stats)}
  end

  defp page_title(:show), do: "Show User"
  defp page_title(:edit), do: "Edit User"

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :highlight, :string, default: "text-white"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-slate-800 border border-slate-700 rounded-2xl p-4">
      <div class="text-xs font-semibold uppercase tracking-wider text-slate-500 mb-1">
        {@label}
      </div>
      <div class={["text-3xl font-bold", @highlight]}>{@value || 0}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="flex justify-between gap-4 py-2.5">
      <dt class="text-sm text-slate-500">{@label}</dt>
      <dd class="text-sm text-slate-200 text-right break-all">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  defp tier_label("pro"), do: "Pro"
  defp tier_label("m3hungry_plus"), do: "M3hungry+"
  defp tier_label(tier), do: tier

  defp format_date(nil), do: "—"
  defp format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

  defp connected_label(token) when is_map(token) and map_size(token) > 0, do: "Connected"
  defp connected_label(_), do: "—"
end
