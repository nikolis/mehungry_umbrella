defmodule MehungryWeb.ShoppingBasketLive.BasicFormComponent do
  @moduledoc """
  Inline create / rename form for a shopping list. Rendered by the parent in the
  sidebar while `@basket_form` is set; `action` is `:new` (create) or `:edit`
  (rename). Save notifies the parent `{:saved, basket}`; Cancel notifies
  `{:cancelled}`.
  """
  use MehungryWeb, :live_component

  alias Mehungry.Inventory

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4 border-b border-ink-panel2">
      <.simple_form
        for={@form}
        id="basket-basic-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-3"
      >
        <input
          type="text"
          name={@form[:title].name}
          value={@form[:title].value}
          placeholder={gettext("List name…")}
          autofocus
          class="h-fit flex-1 px-3 py-2 bg-black/20 border border-ink-panel2 rounded-lg text-parchment text-sm placeholder:text-parchment-dim focus:outline-none focus:border-paprika"
        />
        <div class="flex items-center gap-2">
          <button
            type="submit"
            class="px-3 py-2 bg-paprika hover:bg-paprika-soft text-ink rounded-lg text-sm transition font-bold"
          >
            {if @action == :edit, do: gettext("Rename"), else: gettext("Create")}
          </button>
          <button
            type="button"
            phx-click="cancel"
            phx-target={@myself}
            class="text-parchment-dim hover:text-parchment text-sm font-semibold"
          >
            {gettext("Cancel")}
          </button>
        </div>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{shopping_basket: basket, user: user} = assigns, socket) do
    changeset = Inventory.change_shopping_basket(basket, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user, user)
     |> assign(:shopping_basket, basket)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"shopping_basket" => params}, socket) do
    changeset =
      socket.assigns.shopping_basket
      |> Inventory.change_shopping_basket(with_user(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"shopping_basket" => params}, socket) do
    save(socket, socket.assigns.action, with_user(params, socket))
  end

  def handle_event("cancel", _params, socket) do
    notify_parent({:cancelled})
    {:noreply, socket}
  end

  defp save(socket, :edit, params) do
    case Inventory.update_shopping_basket(socket.assigns.shopping_basket, params) do
      {:ok, basket} ->
        notify_parent({:saved, basket})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, _new, params) do
    case Inventory.create_shopping_basket(params) do
      {:ok, basket} ->
        notify_parent({:saved, basket})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp with_user(params, socket), do: Map.put(params, "user_id", socket.assigns.user.id)

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
