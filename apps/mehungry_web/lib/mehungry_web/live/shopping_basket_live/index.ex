defmodule MehungryWeb.ShoppingBasketLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserProfile
  alias Mehungry.Inventory.ShoppingBasket
  alias Mehungry.Inventory
  import MehungryWeb.ShoppingBasketLive.Components

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    shopping_baskets = Inventory.list_shopping_baskets_for_user(user.id)
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)
    shopping_basket = List.first(shopping_baskets)
    shopping_basket = get_shopping_basket(shopping_basket, user)
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

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit User profile")
    |> assign(:user_profile, Accounts.get_user_profile!(id))
  end

  defp apply_action(socket, :import_items, %{"id" => id} = params) do
    processing_basket = Inventory.get_shopping_basket!(id)
    assign(socket, :processing_basket, processing_basket)
  end

  @impl true
  def handle_event("close-modal", %{"to" => patch}, socket) do
    {:noreply, push_patch(socket, to: "/basket", replace: true)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User profile")
    |> assign(:user_profile, %UserProfile{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing User profiles")
    |> assign(:user_profile, nil)
  end

  @impl true
  def handle_info(
        {MehungryWeb.ShoppingBasketLive.BasicFormComponent, {:saved, shopping_basket}},
        socket
      ) do
    socket =
      socket
      |> assign(:processing_basket, %ShoppingBasket{})

    shopping_baskets = socket.assigns.shopping_baskets + [shopping_basket]
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)

    {:noreply, assign(socket, :shopping_baskets, shopping_baskets)}
  end

  def handle_info(
        {MehungryWeb.ShoppingBasketLive.BasicFormComponent, {:update, shopping_basket}},
        socket
      ) do
    shopping_baskets =
      Enum.filter(socket.assigns.shopping_basket, fn x -> x.id == shopping_basket.id end)

    shopping_baskets = socket.assigns.shopping_baskets + [shopping_basket]
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)

    {:noreply, assign(socket, :shopping_baskets, shopping_baskets)}
  end

  def handle_event("delete_basket", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)
    shopping_basket = Inventory.delete_shopping_basket(%ShoppingBasket{id: id})
    shopping_baskets = Enum.filter(socket.assigns.shopping_baskets, fn x -> x.id != id end)

    {:noreply, assign(socket, :shopping_baskets, shopping_baskets)}
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

  def handle_event("select_shopping_basket", %{"id" => id}, socket) do
    shopping_basket = Inventory.get_shopping_basket!(id)

    {:noreply,
     socket
     |> assign(:shopping_basket, shopping_basket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user_profile = Accounts.get_user_profile!(id)
    {:ok, _} = Accounts.delete_user_profile(user_profile)

    {:noreply, stream_delete(socket, :user_profiles, user_profile)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end