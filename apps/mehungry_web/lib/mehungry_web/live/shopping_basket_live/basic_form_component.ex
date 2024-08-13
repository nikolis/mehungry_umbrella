defmodule MehungryWeb.ShoppingBasketLive.BasicFormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Inventory
  alias Mehungry.History

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
         |> put_flash(:info, "Shopping basket updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_shopping_basket(socket, :index, shopping_basket_params) do
    create_basket(socket, shopping_basket_params)
  end

  defp save_shopping_basket(socket, :import_items, shopping_basket_params) do
    create_basket2(socket, shopping_basket_params)
  end

  defp create_basket2(socket, basket_params_params) do
    user = socket.assigns.user

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

        notify_parent({:update, shopping_basket})

        {:noreply,
         socket
         |> put_flash(:info, "Shopping basket updated")
         |> push_patch(to: socket.assigns.patch)
         |> assign(:shopping_basket, shopping_basket)}
    end
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

  def crete_ingredient_basket(user_meals) do
    user_meals
    |> Enum.reduce([], fn x, acc -> acc ++ x.recipe_user_meals end)
    # Recipe + portions
    |> Enum.map(fn y -> {y.cooking_portions, y.recipe} end)
    # [{2, recipe}]
    |> Enum.map(fn {x, y} -> {x, y.servings, y.recipe_ingredients} end)
    # [{2, [recipe_ingredient, ..]]
    |> Enum.map(fn {x, z, y} ->
      Enum.map(y, fn p -> {x, z, p} end)
      # [[{2, recipe_ingredient}]]
    end)
    |> Enum.reduce([], fn x, acc -> acc ++ x end)
    # [{2, recipe_ingredient}]
    |> Enum.map(fn {x, z, p} -> {p.ingredient_id, p.quantity / z * x, p.measurement_unit.id} end)
    # [{ingredient_id, quantity, measurement_unit_id}]
    # |> Enum.reduce([], fn x, acc -> acc ++ x.recipe.recipe_ingredients end)

    |> Enum.reduce(%{}, fn {ing, quant_out, mu}, acc ->
      with {ing, quant, mu_e} <- Map.get(acc, Integer.to_string(ing)),
           true <- mu == mu_e do
        Map.replace(acc, Integer.to_string(ing), {ing, quant + quant_out, mu_e})
      else
        _ -> Map.put_new(acc, Integer.to_string(ing), {ing, quant_out, mu})
      end
    end)
    |> Map.values()
    |> Enum.map(fn {ing, quant, mu} ->
      %{"ingredient_id" => ing, "quantity" => quant, "measurement_unit_id" => mu}
    end)

    # |> Enum.map(fn x -> {x.ingredient.id, x.quantity, x.measurement_unit.id} end)
    # |> Enum.reduce(%{}, fn {ing, quant, mu}, acc ->
    # with {ing, quant, mu_e} <- Map.get(acc, Integer.to_string(ing)),
    #     true <- mu == mu_e do
    #  Map.replace(acc, Integer.to_string(ing), {ing, quant + quant, mu_e})
    # else
    #  _ -> Map.put_new(acc, Integer.to_string(ing), {ing, quant, mu})
    # end
    # end)
    # |> Map.values()
    # |> Enum.map(fn {ing, quant, mu} ->
    # %{"ingredient_id" => ing, "quantity" => quant, "measurement_unit_id" => mu}
    # end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
