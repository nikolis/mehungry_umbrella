defmodule MehungryWeb.ShoppingBasketLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents
  use MehungryWeb.Presence, :user_tracking

  alias Phoenix.LiveView.JS

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserProfile
  alias Mehungry.Inventory.{ShoppingBasket, BasketItem}
  alias Mehungry.Inventory
  alias Mehungry.FoodData.Usda.SearchClient
  import MehungryWeb.ShoppingBasketLive.Components

  @impl true
  def mount(_params, session, socket) do
    measurement_units =
      Mehungry.Food.list_measurement_units()

    change_basket = Mehungry.Inventory.BasketItem.changeset(%BasketItem{}, %{})

    user = Accounts.get_user_by_session_token(session["user_token"])

    condition_ids =
      user.id
      |> Accounts.get_user_profile_by_user_id()
      |> MehungryWeb.RecipeFlags.opted_in_condition_ids()

    shopping_baskets = Inventory.list_shopping_baskets_for_user(user.id)
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)
    shopping_basket = List.first(shopping_baskets)
    shopping_basket = get_shopping_basket(shopping_basket, user)
    changeset = Inventory.change_shopping_basket(shopping_basket, %{})

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:condition_ids, condition_ids)
     |> assign(change_basket: change_basket)
     |> assign(:shopping_basket, shopping_basket)
     |> assign(:page_title, "Ingredient shopping basket")
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:processing_basket, %ShoppingBasket{})
     # ... existing assigns ...
     |> assign(measurement_units: measurement_units)
     |> assign(show_add_item_modal: false)
     |> assign(search_query: "")
     |> assign(search_results: [])
     |> assign(custom_results: [])
     |> assign(searching: false)
     |> assign(selected_usda_item: nil)
     |> assign(custom_quantity: 1)
     |> assign(custom_unit: "pcs")
     |> assign_form(changeset)
     |> assign(:id, "form-#{System.unique_integer()}")}
  end

  def handle_event("open_add_item_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_add_item_modal: true,
       search_query: "",
       search_results: [],
       custom_results: []
     )}
  end

  def handle_event("close_add_item_modal", _params, socket) do
    {:noreply, assign(socket, show_add_item_modal: false)}
  end

  def handle_event("search_usda", %{"value" => query}, socket) when byte_size(query) >= 2 do
    send(self(), {:perform_search, query})
    {:noreply, assign(socket, searching: true, search_query: query)}
  end

  def handle_event("search_usda", %{"value" => _query}, socket) do
    {:noreply, assign(socket, search_results: [], custom_results: [], searching: false)}
  end

  # Selecting one of the user's own custom ingredients: reuse the USDA confirm
  # panel by shaping the local ingredient into the same map the panel expects.
  def handle_event("select_custom_ingredient", %{"ingredient_id" => id}, socket) do
    ingredient = Mehungry.Food.get_user_ingredient!(socket.assigns.user, id)

    {:noreply,
     assign(socket,
       selected_usda_item: custom_ingredient_to_item(ingredient),
       custom_quantity: 100,
       custom_unit: "g"
     )}
  end

  def handle_event("select_usda_item", %{"fdc_id" => fdc_id}, socket) do
    case SearchClient.get_food_details(fdc_id) do
      {:ok, food} ->
        {:noreply,
         assign(socket,
           selected_usda_item: food,
           custom_quantity: 100,
           custom_unit: "g"
         )}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  def handle_event("add_usda_item", %{"quantity" => quantity, "unit" => unit}, socket) do
    item = %{
      name: socket.assigns.selected_usda_item["description"],
      quantity: elem(Float.parse(quantity), 0),
      unit: unit,
      nutrition: %{
        calories: get_nutrition_value(socket.assigns.selected_usda_item, "Energy"),
        protein: get_nutrition_value(socket.assigns.selected_usda_item, "Protein"),
        fat: get_nutrition_value(socket.assigns.selected_usda_item, "Total Fat"),
        carbs: get_nutrition_value(socket.assigns.selected_usda_item, "Carbohydrates")
      },
      usda_fdc_id: socket.assigns.selected_usda_item["fdcId"]
    }

    case Inventory.add_item(socket.assigns.shopping_basket.id, item) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(selected_usda_item: nil, show_add_item_modal: false)
         |> put_flash(:info, "Item added with nutrition data!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add item")}
    end
  end

  def handle_event(
        "add_plain_item",
        %{
          "basket_item" => %{"measurement_unit_id" => measurement_unit_id},
          "name" => name,
          "quantity" => quantity
        },
        socket
      ) do
    item = %{
      name: name,
      quantity: elem(Float.parse(quantity), 0),
      measurement_unit_id: measurement_unit_id,
      nutrition: nil,
      usda_fdc_id: nil
    }

    %ShoppingBasket{} = shopping_basket = socket.assigns.shopping_basket

    case Inventory.add_item(shopping_basket.id, item) do
      {:ok, item} ->
        basket = %ShoppingBasket{
          shopping_basket
          | basket_items: shopping_basket.basket_items ++ [item]
        }

        {:noreply,
         socket
         |> assign(show_add_item_modal: false)
         |> assign(shopping_basket: basket)
         |> put_flash(:info, "Item added to your list!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add item")}
    end
  end

  def handle_event("delete_basket", %{"id" => id}, socket) do
    {id, _} = Integer.parse(id)
    Inventory.delete_shopping_basket(%ShoppingBasket{id: id})
    shopping_baskets = Inventory.list_shopping_baskets_for_user(socket.assigns.user.id)
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)

    shopping_basket =
      if is_nil(socket.assigns.shopping_basket) do
        List.first(shopping_baskets)
      else
        socket.assigns.shopping_basket
      end

    {:noreply,
     socket
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:shopping_basket, shopping_basket)
     |> assign(:processing_basket, %ShoppingBasket{})}
  end

  def handle_event("toggle_basket", %{"id" => id}, socket) do
    id = String.to_integer(id)

    %ShoppingBasket{} = current_basket = socket.assigns.shopping_basket

    item =
      Enum.find(
        current_basket.basket_ingredients ++
          current_basket.basket_items,
        fn x -> x.id == id end
      )

    shopping_basket =
      if(item.__struct__ == Mehungry.Inventory.BasketIngredient) do
        rest =
          Enum.filter(current_basket.basket_ingredients, fn x ->
            x.id != item.id
          end)

        {:ok, ingredient} = Inventory.toggle_basket_ingredient(item)
        all_ingredients = rest ++ [ingredient]

        %ShoppingBasket{
          current_basket
          | basket_ingredients: all_ingredients
        }
      else
        rest =
          Enum.filter(current_basket.basket_items, fn x -> x.id != item.id end)

        {:ok, basket_item} = Inventory.toggle_basket_ingredient(item)

        %ShoppingBasket{
          current_basket
          | basket_items: rest ++ [basket_item]
        }
      end

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

  @impl true
  def handle_event("close-modal", _, socket) do
    {:noreply, push_patch(socket, to: "/basket", replace: true)}
  end

  defp get_nutrition_value(food, nutrient_name) do
    Enum.find_value(food["food_nutrients"] || [], fn n ->
      if String.contains?(n.nutrient_name, nutrient_name) do
        n.value
      end
    end) || 0
  end

  defp get_shopping_basket(shopping_basket, user) do
    case shopping_basket do
      nil ->
        %ShoppingBasket{user_id: user.id, basket_ingredients: [], basket_items: []}

      %ShoppingBasket{} = shopping_basket ->
        %ShoppingBasket{
          shopping_basket
          | basket_ingredients:
              Mehungry.Utils.sort_ingredients_for_basket(shopping_basket.basket_ingredients)
        }
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    maybe_track_user(%{}, socket)

    socket
    |> assign(:page_title, "Edit User profile")
    |> assign(:user_profile, Accounts.get_user_profile!(id))
  end

  defp apply_action(socket, :import_items, %{"id" => id} = _params) do
    maybe_track_user(%{}, socket)

    basket = Inventory.get_shopping_basket!(id)
    assign(socket, :processing_basket, basket)
  end

  defp apply_action(socket, :new, _params) do
    maybe_track_user(%{}, socket)

    socket
    |> assign(:page_title, "New User profile")
    |> assign(:user_profile, %UserProfile{})
  end

  defp apply_action(socket, :index, _params) do
    maybe_track_user(%{}, socket)

    socket
    |> assign(:page_title, "Listing User profiles")
    |> assign(:user_profile, nil)
  end

  @impl true
  def handle_info(
        {MehungryWeb.ShoppingBasketLive.BasicFormComponent, {:saved, _shopping_basket}},
        socket
      ) do
    shopping_baskets = Inventory.list_shopping_baskets_for_user(socket.assigns.user.id)
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)

    shopping_basket =
      if is_nil(socket.assigns.shopping_basket) do
        List.first(shopping_baskets)
      else
        socket.assigns.shopping_basket
      end

    {:noreply,
     socket
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:shopping_basket, shopping_basket)
     |> assign(:processing_basket, %ShoppingBasket{})}
  end

  def handle_info(
        {MehungryWeb.ShoppingBasketLive.BasicFormComponent, {:update, shopping_basket}},
        socket
      ) do
    shopping_baskets =
      Enum.filter(socket.assigns.shopping_baskets, fn x -> x.id != shopping_basket.id end)

    shopping_baskets = shopping_baskets ++ [shopping_basket]
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)

    shopping_basket =
      if socket.assigns.shopping_basket.id == shopping_basket.id do
        shopping_basket
      else
        socket.assigns.shopping_basket
      end

    {:noreply,
     socket
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:shopping_basket, shopping_basket)
     |> push_patch(to: "/basket")}
  end

  def handle_info(
        {MehungryWeb.ShoppingBasketLive.FormComponent, {:update, shopping_basket}},
        socket
      ) do
    shopping_baskets =
      Enum.filter(socket.assigns.shopping_baskets, fn x -> x.id != shopping_basket.id end)

    shopping_baskets = shopping_baskets ++ [shopping_basket]
    shopping_baskets = Enum.sort_by(shopping_baskets, fn x -> x.updated_at end, :desc)

    shopping_basket =
      if socket.assigns.shopping_basket.id == shopping_basket.id do
        shopping_basket
      else
        socket.assigns.shopping_basket
      end

    {:noreply,
     socket
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:shopping_basket, shopping_basket)}
  end

  def handle_info({:perform_search, query}, socket) do
    # The user's own private ingredients, surfaced alongside USDA results. Only
    # rows owned by this user are kept (global local-DB rows stay out of the
    # USDA-centric basket flow).
    user_id = socket.assigns.user.id

    custom_results =
      Mehungry.Food.IngredientSearch.search(query, [], user_id)
      |> Enum.filter(&(&1.user_id == user_id))

    case SearchClient.search_foods(query, 5) do
      {:ok, results} ->
        {:noreply,
         assign(socket, search_results: results, custom_results: custom_results, searching: false)}

      {:error, _error} ->
        {:noreply,
         assign(socket, search_results: [], custom_results: custom_results, searching: false)}
    end
  end

  # Shapes a private ingredient into the map the USDA confirm panel expects
  # (string "description"/"fdcId"/"food_nutrients" keys), so selecting a custom
  # ingredient flows through the existing quantity-confirm + add_usda_item path.
  defp custom_ingredient_to_item(ingredient) do
    food_nutrients =
      Enum.map(ingredient.ingredient_nutrients, fn n ->
        %{nutrient_name: nutrient_name(n), value: n.amount || 0}
      end)

    %{
      "description" => ingredient.name,
      "fdcId" => nil,
      "food_nutrients" => food_nutrients
    }
  end

  defp nutrient_name(%{nutrient: %{name: name}}) when is_binary(name), do: name
  defp nutrient_name(_), do: ""

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
