defmodule MehungryWeb.BasketLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  alias Mehungry.Inventory.BasketParams
  alias Mehungry.Inventory
  alias Mehungry.Accounts
  alias Mehungry.History

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    shopping_baskets = Inventory.list_shopping_baskets_for_user(user.id)

    shopping_basket =
      case Enum.empty?(shopping_baskets) do
        true ->
          nil

        false ->
          {:ok, shopping_basket} = Enum.fetch(shopping_baskets, 0)
          shopping_basket
      end

    basket_params = %BasketParams{}
    changeset = Inventory.change_basket_params(basket_params, %{})

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:shopping_basket, shopping_basket)
     |> assign(:basket_params, basket_params)
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:changeset, changeset)}
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  defp apply_action(socket, :edit, %{"id" => _id} = _params) do
    socket =
      socket
      |> assign(:page_title, "Edit Basket")

    # |> assign(:user_meal, user_meal)
    socket
  end

  defp apply_action(socket, :new, %{"start" => _start_date, "end" => _end_date} = _params) do
    socket =
      socket
      |> assign(:page_title, "Create Meal")

    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_event("delete_basket", %{"id" => basket_id}, socket) do
    bs = Inventory.get_shopping_basket!(basket_id)
    Inventory.delete_shopping_basket(bs)

    {:noreply,
     socket
     |> assign(:shopping_basket, nil)}
  end

  def handle_event("save", %{"basket_params" => basket_params_params}, socket) do
    create_basket(socket, socket.assigns.live_action, basket_params_params)
  end

  @impl true
  def handle_event("validate", %{"basket_params" => basket_params_params}, socket) do
    changeset =
      socket.assigns.basket_params
      |> Inventory.change_basket_params(basket_params_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("got_item", %{"id" => id}, socket) do
    bi = Inventory.get_basket_ingredient!(id)
    _bi = Inventory.update_basket_ingredient(bi, %{in_storage: !bi.in_storage})
    shopping_baskets = Inventory.list_shopping_baskets_for_user(socket.assigns.user.id)

    shopping_basket =
      case Enum.empty?(shopping_baskets) do
        true ->
          nil

        false ->
          {:ok, shopping_basket} = Enum.fetch(shopping_baskets, 0)
          shopping_basket
      end

    {:noreply,
     socket
     |> assign(:shopping_basket, shopping_basket)}
  end

  def checked(id) do
    bi = Inventory.get_basket_ingredient!(id)

    case bi.in_storage do
      true ->
        "checked"

      _ ->
        ""
    end
  end

  #     case Map.get(acc, Integer.to_string(ing)) do
  #        nil ->
  #          Map.put_new(acc, Integer.to_string(ing), {ing, quant, mu})
  #
  #        {ing, quant, mu_e} ->
  #          if mu == mu_e do
  #            Map.replace(acc, Integer.to_string(ing), {ing, quant + quant, mu_e})
  #          else
  #            Map.put_new(acc, Integer.to_string(ing), {ing, quant, mu})
  #          end
  #      end

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
      %{ingredient_id: ing, quantity: quant, measurement_unit_id: mu}
    end)
  end

  defp create_basket(socket, _save_action, basket_params_params) do
    user = socket.assigns.user

    changeset =
      socket.assigns.basket_params
      |> Inventory.change_basket_params(basket_params_params)
      |> Map.put(:action, :validate)

    case changeset.valid? do
      false ->
        {:noreply, assign(socket, :changeset, changeset)}

      true ->
        start_dt = basket_params_params["start_dt"]
        st_dt = NaiveDateTime.from_iso8601!(start_dt <> "T00:00:00")

        end_dt = basket_params_params["end_dt"]
        en_dt = NaiveDateTime.from_iso8601!(end_dt <> "T23:59:59")

        user_meals =
          History.list_history_user_meals_for_user(socket.assigns.user.id, st_dt, en_dt)

        all_ingredients = crete_ingredient_basket(user_meals)

        params = %{
          start_dt: st_dt,
          end_dt: en_dt,
          basket_ingredients: all_ingredients,
          user_id: user.id
        }

        shopping_basket = Inventory.create_shopping_basket(params)

        {:noreply,
         socket
         |> assign(:shopping_basket, shopping_basket)}
    end
  end
end
