defmodule MehungryWeb.ShoppingBasketLive.BasicFormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Inventory

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.simple_form
        for={@form}
        id="basket-basic-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="side-form "
      >
          <.input field={@form[:user_id]} type="hidden"  />
          <.input field={@form[:title]} type="text" class="mt-2 mx-2" /> 
        <:actions>
          <div style="margin-inline: auto; width: 88%; ">
            <button type="submit" class="button bg-complementary  " phx-click={
      JS.remove_class("active", to: "#basket-basic-form.active")
      } >SAVE</button>
            <button class="list_button_cancel"  phx-click={
      JS.remove_class("active", to: "#basket-basic-form.active")
      }> CANCEL </button>
          </div>
        </:actions>
      </.simple_form>

    </div>
    """
  end

  @impl true
  def update(%{shopping_basket: basket, user: user} = assigns, socket) do
    changeset = Inventory.change_shopping_basket(Map.put(basket, "user_id", user.id))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user, user)
     |> assign(:shopping_basket, basket)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"shopping_basket" => shopping_basket_params}, socket) do
    shopping_basket_params = Map.put(shopping_basket_params, "user_id", socket.assigns.user.id)

    changeset =
      socket.assigns.shopping_basket
      |> Inventory.change_shopping_basket(shopping_basket_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"shopping_basket" => shopping_basket_params}, socket) do
    shopping_basket_params = Map.put(shopping_basket_params, "user_id", socket.assigns.user.id)

    save_shopping_basket(socket, socket.assigns.action, shopping_basket_params)
  end

  defp save_shopping_basket(socket, :edit, shopping_basket_params) do
    case Inventory.update_shopping_basket(socket.assigns.shopping_basket, shopping_basket_params) do
      {:ok, shopping_basket} ->
        notify_parent({:saved, shopping_basket})

        {:noreply,
         socket
         |> put_flash(:info, "User profile updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_shopping_basket(socket, :index, shopping_basket_params) do
    create_basket(socket, shopping_basket_params)
  end

  defp create_basket(socket, basket_params_params) do
    shopping_basket = Inventory.create_shopping_basket(basket_params_params)

    case shopping_basket do
      {:ok, basket} ->
        notify_parent({:saved, basket})

      _ ->
        ""
    end

    {:noreply,
     socket
     |> assign(:shopping_basket, shopping_basket)
     |> push_patch(to: socket.assigns.patch)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
