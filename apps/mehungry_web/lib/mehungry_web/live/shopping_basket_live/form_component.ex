defmodule MehungryWeb.ShoppingBasketLive.FormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Inventory
  alias Mehungry.History

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle >Crete a shopping list by selecting a range of dates (meals will be pulled from your callendar schedule) </:subtitle>
      </.header>
          <div style="" phx-update="ignore" id="container" phx-hook="DatePicker"> 
              <input name="endtDate" type="hidden" placeholder="Select Date.." data-input>
          </div>

      <.simple_form
        for={@form}
        id="basket-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save">
          <.input field={@form[:start_dt]} type="hidden"  />
          <.input field={@form[:end_dt]} type="hidden" label="Intro" /> 
        <:actions>
          <.button type="primary"  phx-disable-with="Saving...">Create Basket</.button>
        </:actions>
      </.simple_form>

    </div>
    """
  end

  @impl true
  def update(%{shopping_basket: basket, user: user, patch: _patch} = assigns, socket) do
    changeset = Inventory.change_shopping_basket(basket, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user, user)
     |> assign(:shopping_basket, basket)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"shopping_basket" => shopping_basket_params}, socket) do
    changeset =
      socket.assigns.shopping_basket
      |> Inventory.change_shopping_basket(shopping_basket_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"shopping_basket" => shopping_basket_params}, socket) do
    save_shopping_basket(socket, socket.assigns.action, shopping_basket_params)
  end

  defp save_shopping_basket(socket, :edit, shopping_basket_params) do
    case Inventory.update_shopping_basket(socket.assigns.shopping_basket, shopping_basket_params) do
      {:ok, shopping_basket} ->
        IO.inspect("Save shopping basket ok")

        notify_parent({:saved, shopping_basket})

        {:noreply,
         socket
         |> put_flash(:info, "Shopping basket updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.inspect("Save shopping basket ok not")

        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_shopping_basket(socket, :import_items, shopping_basket_params) do
    create_basket(socket, shopping_basket_params)
  end

  defp create_basket(socket, basket_params_params) do
    user = socket.assigns.user
    IO.inspect(socket.assigns.shopping_basket, label: "Basket from assigns in create")
    IO.inspect(basket_params_params, label: "basket_params")

    changeset =
      socket.assigns.shopping_basket
      |> Inventory.change_shopping_basket(basket_params_params)
      |> Map.put(:action, :validate)

    case changeset.valid? do
      false ->
        {:noreply, assign_form(socket, changeset)}

      true ->
        start_dt = basket_params_params["start_dt"]
        st_dt = NaiveDateTime.from_iso8601!(start_dt)

        end_dt = basket_params_params["end_dt"]
        en_dt = NaiveDateTime.from_iso8601!(end_dt)

        user_meals =
          History.list_history_user_meals_for_user(socket.assigns.user.id, st_dt, en_dt)

        all_ingredients = crete_ingredient_basket(user_meals)

        params = %{
          "start_dt" => st_dt,
          "end_dt" => en_dt,
          "basket_ingredients" => all_ingredients,
          "user_id" => user.id
        }

        {:ok, shopping_basket} =
          Inventory.update_shopping_basket(socket.assigns.shopping_basket, params)

        IO.inspect(shopping_basket, label: "Here when leave")
        notify_parent({:update, shopping_basket})

        {:noreply,
         socket
         |> put_flash(:info, "Shopping basket updated")
         |> push_patch(to: socket.assigns.patch)
         |> assign(:shopping_basket, shopping_basket)}
    end
  end

  defp crete_ingredient_basket(user_meals) do
    user_meals
    |> Enum.reduce([], fn x, acc -> acc ++ x.recipe_user_meals end)
    |> Enum.reduce([], fn x, acc -> acc ++ x.recipe.recipe_ingredients end)
    |> Enum.map(fn x -> {x.ingredient.id, x.quantity, x.measurement_unit.id} end)
    |> Enum.reduce(%{}, fn {ing, quant, mu}, acc ->
      with {ing, quant, mu_e} <- Map.get(acc, Integer.to_string(ing)),
           true <- mu == mu_e do
        Map.replace(acc, Integer.to_string(ing), {ing, quant + quant, mu_e})
      else
        _ -> Map.put_new(acc, Integer.to_string(ing), {ing, quant, mu})
      end
    end)
    |> Map.values()
    |> Enum.map(fn {ing, quant, mu} ->
      %{"ingredient_id" => ing, "quantity" => quant, "measurement_unit_id" => mu}
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
