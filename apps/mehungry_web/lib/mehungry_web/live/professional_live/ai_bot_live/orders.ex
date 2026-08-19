defmodule MehungryWeb.AiBotLive.Orders do
  @moduledoc """
  Admin UI for ad-hoc recipe orders: generate N recipes for a setup, outside
  the monthly calendar. Fulfilled by `RecipeOrderWorker`; results land in the
  review queue.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.{AiBotConfig, RecipeOrder}
  alias Mehungry.ObanWorkers.RecipeOrderWorker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:orders, Bot.list_recipe_orders())
     |> assign(:setups, Bot.list_active_recipe_setups())
     |> assign(:users, Accounts.list_users())
     |> assign(:meal_types, AiBotConfig.meal_types())
     |> assign(:form, nil)
     |> assign(:page_title, "AI Bot Recipe Orders")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :form, nil)

  defp apply_action(socket, :new, _params) do
    assign(socket, :form, to_form(Bot.change_recipe_order(%RecipeOrder{quantity: 5})))
  end

  @impl true
  def handle_event("validate", %{"recipe_order" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :form,
       to_form(Bot.change_recipe_order(%RecipeOrder{}, params), action: :validate)
     )}
  end

  def handle_event("save", %{"recipe_order" => params}, socket) do
    case Bot.create_recipe_order(params) do
      {:ok, order} ->
        %{order_id: order.id}
        |> RecipeOrderWorker.new()
        |> Oban.insert()

        {:noreply,
         socket
         |> assign(:orders, Bot.list_recipe_orders())
         |> put_flash(:info, "Order placed — generating #{order.quantity} recipe(s).")
         |> push_patch(to: ~p"/professional/ai-bot/orders")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket =
      case id |> Bot.get_recipe_order!() |> Bot.delete_recipe_order() do
        {:ok, _order} ->
          socket
          |> assign(:orders, Bot.list_recipe_orders())
          |> put_flash(:info, "Order deleted.")

        {:error, _reason} ->
          put_flash(socket, :error, "Could not delete this order.")
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-xl font-bold text-white">Recipe Orders</h1>
        <p class="text-sm text-slate-400 mt-0.5">
          Generate a batch of recipes for a setup, on demand. Results appear in the <.link
            navigate={~p"/professional/ai-bot/review"}
            class="text-primary-400 hover:underline"
          >review queue</.link>.
        </p>
      </div>
      <.link
        patch={~p"/professional/ai-bot/orders/new"}
        class="flex items-center gap-1 px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
      >
        <.icon name="hero-plus" class="h-4 w-4" /> New Order
      </.link>
    </div>

    <div class="flex gap-6">
      <div class="flex-1 min-w-0 space-y-2">
        <div
          :for={order <- @orders}
          class="group bg-slate-800 border border-slate-700/60 rounded-xl p-4"
        >
          <div class="flex items-center justify-between">
            <div>
              <div class="font-semibold text-white text-sm">
                {order.recipe_setup && order.recipe_setup.name}
              </div>
              <div class="text-xs text-slate-400 mt-0.5">
                {order.quantity} × {order.meal_type || "mixed meals"} · {order.language_name}
              </div>
            </div>
            <div class="flex items-center gap-3">
              <div class="text-right">
                <span class={[
                  "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold border",
                  status_class(order.status)
                ]}>
                  {order.status}
                </span>
                <div class="text-[11px] text-slate-500 mt-1">
                  {order.completed_count}/{order.quantity} done
                </div>
              </div>
              <button
                phx-click="delete"
                phx-value-id={order.id}
                data-confirm="Delete this order? Already-generated recipes are kept in the review queue."
                class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-red-400 hover:bg-red-500/10 text-xs opacity-0 group-hover:opacity-100 transition-all"
              >
                <.icon name="hero-trash" class="h-3.5 w-3.5" /> Delete
              </button>
            </div>
          </div>
        </div>
        <p :if={@orders == []} class="text-sm text-slate-500">No orders yet.</p>
      </div>

      <div :if={@form} class="w-96 flex-shrink-0">
        <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-6">
          <h2 class="text-base font-semibold text-white mb-5">New Order</h2>
          <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <div>
              <label class="block text-xs text-slate-400 mb-1">Setup</label>
              <.input
                field={@form[:recipe_setup_id]}
                type="select"
                prompt="Select a setup…"
                options={Enum.map(@setups, &{&1.name, &1.id})}
                class={input_class()}
              />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Bot user (author)</label>
              <.input
                field={@form[:bot_user_id]}
                type="select"
                prompt="Select a user…"
                options={Enum.map(@users, &{&1.name || &1.email, &1.id})}
                class={input_class()}
              />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">How many recipes</label>
              <.input field={@form[:quantity]} type="number" min="1" max="50" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Meal type</label>
              <.input
                field={@form[:meal_type]}
                type="select"
                prompt="Mixed (cycle across meals)"
                options={Enum.map(@meal_types, &{humanize_meal(&1), &1})}
                class={input_class()}
              />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Language</label>
              <.input
                field={@form[:language_name]}
                type="text"
                value={@form[:language_name].value || "En"}
                class={input_class()}
              />
            </div>
            <div class="flex items-center gap-2 pt-2">
              <button
                type="submit"
                class="px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium"
              >
                Place order
              </button>
              <.link
                patch={~p"/professional/ai-bot/orders"}
                class="px-4 py-2 rounded-lg text-slate-400 hover:text-white text-sm"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp humanize_meal(meal_type), do: meal_type |> String.replace("_", " ") |> String.capitalize()

  defp status_class("completed"), do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30"
  defp status_class("generating"), do: "bg-amber-500/20 text-amber-300 border-amber-500/30"
  defp status_class("failed"), do: "bg-red-500/20 text-red-300 border-red-500/30"
  defp status_class(_), do: "bg-slate-700/50 text-slate-400 border-slate-600/40"

  defp input_class,
    do:
      "w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
end
