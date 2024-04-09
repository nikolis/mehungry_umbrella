defmodule MehungryWeb.BasketLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  import MehungryWeb.CoreComponents
  import MehungryWeb.BasketLive.Components

  alias MehungryWeb.BasketLive.Components
  alias Mehungry.Inventory.BasketParams
  alias Mehungry.Inventory.BasketSelectionParams
  alias Mehungry.Inventory.ShoppingBasket
  alias Mehungry.Inventory
  alias Mehungry.Accounts
  alias Mehungry.History

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    shopping_baskets = Inventory.list_shopping_baskets_for_user(user.id)
    shopping_basket = List.first(shopping_baskets)
    shopping_basket = get_shopping_basket(shopping_basket, user)
    IO.inspect("Mount")
    changeset = Inventory.change_shopping_basket(shopping_basket, %{})

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:shopping_basket, shopping_basket)
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:processing_basket, %ShoppingBasket{})
     |> assign_form(changeset)
     |> assign(:id, "form-#{System.unique_integer()}")}
  end

  defp get_shopping_basket(shopping_basket, user) do
    case shopping_basket do
      nil ->
        %ShoppingBasket{user_id: user.id, basket_ingredients: []}

      shopping_basket ->
        shopping_basket = %ShoppingBasket{
          shopping_basket
          | basket_ingredients:
              Mehungry.Utils.sort_ingredients_for_basket(shopping_basket.basket_ingredients)
        }
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  defp apply_action(socket, :import_items, %{"id" => id} = params) do
    socket
  end

  defp apply_action(socket, :edit, %{"id" => _id} = _params) do
    socket
  end

  defp apply_action(socket, :new, %{"start" => _start_date, "end" => _end_date} = _params) do
    socket
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info({MehungryWeb.BasketLive.BasicFormComponent, {:saved, shopping_basket}}, socket) do
    {:noreply,
     assign(
       socket,
       :shopping_baskets,
       Enum.into(socket.assigns.shopping_baskets, [shopping_basket])
     )}
  end

  def handle_event("select_shopping_basket", %{"id" => id}, socket) do
    shopping_basket = Inventory.get_shopping_basket!(id)

    {:noreply,
     socket
     |> assign(:shopping_basket, shopping_basket)}
  end

  @impl true
  def handle_event("close-modal", %{"to" => patch}, socket) do
    IO.inspect(patch)
    {:noreply, push_patch(socket, to: "/basket", replace: true)}
  end

  def handle_event("delete_basket", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)
    shopping_basket = Inventory.delete_shopping_basket(%ShoppingBasket{id: id})

    {:noreply, socket}
  end

  def handle_event("toggle_basket", %{"id" => id}, socket) do
    id = String.to_integer(id)

    {[ingredient], rest} =
      Enum.split_with(socket.assigns.shopping_basket.basket_ingredients, fn x -> x.id == id end)

    {:ok, ingredient} = Inventory.toggle_basket_ingredient(ingredient)
    all_ingredients = rest ++ [ingredient]

    shopping_basket = %ShoppingBasket{
      socket.assigns.shopping_basket
      | basket_ingredients: Mehungry.Utils.sort_ingredients_for_basket(all_ingredients)
    }

    {:noreply,
     socket
     |> assign(:shopping_basket, shopping_basket)}
  end

  def handle_event("save", %{"basket_params" => basket_params_params}, socket) do
    create_basket(socket, socket.assigns.live_action, basket_params_params)
  end

  @impl true
  def handle_event("validate", %{"shopping_basket" => shopping_basket_params}, socket) do
    changeset =
      Inventory.change_shopping_basket(socket.assigns.shopping_basket, shopping_basket_params)

    socket = assign_form(socket, changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_basket", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/calendar/#{id}", replace: true)}
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

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
