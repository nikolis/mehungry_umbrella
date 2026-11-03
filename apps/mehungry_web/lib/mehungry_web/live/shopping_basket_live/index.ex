defmodule MehungryWeb.ShoppingBasketLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents
  use MehungryWeb.Presence, :user_tracking

  alias Phoenix.LiveView.JS

  alias Mehungry.Inventory
  alias Mehungry.Inventory.{ShoppingBasket, BasketItem, BasketIngredient}
  alias Mehungry.FoodData.Usda.SearchClient
  import MehungryWeb.ShoppingBasketLive.Components

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    measurement_units = Mehungry.Food.list_measurement_units()
    change_basket = BasketItem.changeset(%BasketItem{}, %{})

    shopping_baskets = load_baskets(user.id)
    # Deep-link support (?basket_id=): open the requested basket if the user owns
    # it (e.g. arriving from the calendar's "Shopping list" button); otherwise
    # fall back to the most-recently-updated one.
    shopping_basket =
      shopping_baskets
      |> select_initial_basket(params["basket_id"])
      |> blank_basket_fallback(user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Shopping Lists"))
     |> assign(:change_basket, change_basket)
     |> assign(:shopping_basket, shopping_basket)
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:processing_basket, %ShoppingBasket{})
     |> assign(:basket_form, nil)
     |> assign(:editing_item, nil)
     |> assign(:measurement_units, measurement_units)
     |> assign(:show_add_item_modal, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:custom_results, [])
     |> assign(:searching, false)
     |> assign(:selected_usda_item, nil)
     |> assign(:id, "add-item-modal")}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # List management (create / rename / delete / select)
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_basket_form", _params, socket) do
    {:noreply, assign(socket, :basket_form, %{action: :new, basket: %ShoppingBasket{}})}
  end

  def handle_event("edit_basket", %{"id" => id}, socket) do
    case owned_basket(socket, id) do
      nil -> {:noreply, socket}
      basket -> {:noreply, assign(socket, :basket_form, %{action: :edit, basket: basket})}
    end
  end

  def handle_event("cancel_basket_form", _params, socket) do
    {:noreply, assign(socket, :basket_form, nil)}
  end

  def handle_event("select_shopping_basket", %{"id" => id}, socket) do
    case owned_basket(socket, id) do
      nil -> {:noreply, socket}
      basket -> {:noreply, assign(socket, shopping_basket: basket, editing_item: nil)}
    end
  end

  def handle_event("delete_basket", %{"id" => id}, socket) do
    with {id, _} <- Integer.parse(id),
         %ShoppingBasket{} = basket <- owned_basket(socket, id) do
      Inventory.delete_shopping_basket(basket)
      shopping_baskets = load_baskets(socket.assigns.current_user.id)

      # If the deleted basket was the one on screen, fall back to another.
      active =
        if socket.assigns.shopping_basket.id == basket.id do
          blank_basket_fallback(List.first(shopping_baskets), socket.assigns.current_user)
        else
          socket.assigns.shopping_basket
        end

      {:noreply,
       socket
       |> assign(:shopping_baskets, shopping_baskets)
       |> assign(:shopping_basket, active)
       |> assign(:basket_form, nil)
       |> put_flash(:info, gettext("List deleted"))}
    else
      _ -> {:noreply, socket}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Add-item modal
  # ──────────────────────────────────────────────────────────────────────────

  def handle_event("open_add_item_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_add_item_modal: true,
       search_query: "",
       search_results: [],
       custom_results: [],
       selected_usda_item: nil,
       searching: false
     )}
  end

  def handle_event("close_add_item_modal", _params, socket) do
    {:noreply, assign(socket, show_add_item_modal: false)}
  end

  def handle_event("search_usda", %{"value" => query}, socket) when byte_size(query) >= 2 do
    send(self(), {:perform_search, query})
    {:noreply, assign(socket, searching: true, search_query: query)}
  end

  def handle_event("search_usda", %{"value" => query}, socket) do
    {:noreply,
     assign(socket, search_query: query, search_results: [], custom_results: [], searching: false)}
  end

  # Selecting one of the user's own custom ingredients: reuse the USDA confirm
  # panel by shaping the local ingredient into the same map the panel expects.
  def handle_event("select_custom_ingredient", %{"ingredient_id" => id}, socket) do
    ingredient = Mehungry.Food.get_user_ingredient!(socket.assigns.current_user, id)

    {:noreply, assign(socket, selected_usda_item: custom_ingredient_to_item(ingredient))}
  end

  def handle_event("select_usda_item", %{"fdc_id" => fdc_id}, socket) do
    case SearchClient.get_food_details(fdc_id) do
      {:ok, food} -> {:noreply, assign(socket, selected_usda_item: food)}
      {:error, _error} -> {:noreply, put_flash(socket, :error, gettext("Could not load that item"))}
    end
  end

  def handle_event("cancel_usda_selection", _params, socket) do
    {:noreply, assign(socket, selected_usda_item: nil)}
  end

  # Quantity + unit now come from the confirm form's submit params, so the typed
  # value is actually used (previously pinned to a default and added as 100 g).
  def handle_event("add_usda_item", %{"quantity" => quantity, "unit" => unit}, socket) do
    selected = socket.assigns.selected_usda_item

    item = %{
      name: selected["description"],
      quantity: parse_quantity(quantity) || 1.0,
      # Free-text unit label — USDA/custom items have no MeasurementUnit row.
      description: unit,
      measurement_unit_id: nil,
      nutrition: %{
        calories: get_nutrition_value(selected, "Energy"),
        protein: get_nutrition_value(selected, "Protein"),
        fat: get_nutrition_value(selected, "Total Fat"),
        carbs: get_nutrition_value(selected, "Carbohydrates")
      },
      usda_fdc_id: selected["fdcId"]
    }

    case Inventory.add_item(socket.assigns.shopping_basket.id, item) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(selected_usda_item: nil, show_add_item_modal: false)
         |> refresh_active_basket()
         |> put_flash(:info, gettext("Item added with nutrition data"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add item"))}
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
      quantity: parse_quantity(quantity) || 1.0,
      measurement_unit_id: measurement_unit_id,
      nutrition: nil,
      usda_fdc_id: nil
    }

    case Inventory.add_item(socket.assigns.shopping_basket.id, item) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> assign(show_add_item_modal: false)
         |> refresh_active_basket()
         |> put_flash(:info, gettext("Item added to your list"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to add item"))}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Per-item actions (toggle acquired / edit / delete)
  # ──────────────────────────────────────────────────────────────────────────

  def handle_event("toggle_basket", %{"id" => id, "type" => type}, socket) do
    case find_entry(socket, type, id) do
      nil ->
        {:noreply, socket}

      entry ->
        {:ok, _} = Inventory.toggle_basket_ingredient(entry)
        {:noreply, refresh_active_basket(socket)}
    end
  end

  def handle_event("edit_item", %{"id" => id, "type" => type}, socket) do
    case find_entry(socket, type, id) do
      nil -> {:noreply, socket}
      entry -> {:noreply, assign(socket, :editing_item, entry)}
    end
  end

  def handle_event("cancel_edit_item", _params, socket) do
    {:noreply, assign(socket, :editing_item, nil)}
  end

  def handle_event("update_item", %{"item_id" => id, "item_type" => type} = params, socket) do
    quantity = parse_quantity(params["quantity"])

    result =
      case find_entry(socket, type, id) do
        %BasketItem{} = item ->
          Inventory.update_basket_item(item, prune(%{quantity: quantity, name: params["name"]}))

        %BasketIngredient{} = ingredient ->
          Inventory.update_basket_ingredient(ingredient, prune(%{quantity: quantity}))

        nil ->
          :not_found
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> assign(:editing_item, nil) |> refresh_active_basket()}

      :not_found ->
        {:noreply, assign(socket, :editing_item, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update the item"))}
    end
  end

  def handle_event("delete_item", %{"id" => id, "type" => type}, socket) do
    case find_entry(socket, type, id) do
      %BasketItem{} = item ->
        Inventory.delete_basket_item(item)
        {:noreply, socket |> assign(:editing_item, nil) |> refresh_active_basket()}

      %BasketIngredient{} = ingredient ->
        Inventory.delete_basket_ingredient(ingredient)
        {:noreply, socket |> assign(:editing_item, nil) |> refresh_active_basket()}

      nil ->
        {:noreply, socket}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Params / actions
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :import_items, %{"id" => id}) do
    maybe_track_user(%{}, socket)

    case owned_basket(socket, id) do
      nil -> push_patch(socket, to: ~p"/basket")
      basket -> assign(socket, :processing_basket, basket)
    end
  end

  defp apply_action(socket, :index, _params) do
    maybe_track_user(%{}, socket)
    assign(socket, :processing_basket, %ShoppingBasket{})
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Messages from the basket form components
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({MehungryWeb.ShoppingBasketLive.BasicFormComponent, {:cancelled}}, socket) do
    {:noreply, assign(socket, :basket_form, nil)}
  end

  def handle_info({MehungryWeb.ShoppingBasketLive.BasicFormComponent, {:saved, basket}}, socket) do
    shopping_baskets = load_baskets(socket.assigns.current_user.id)

    active =
      if socket.assigns.shopping_basket && socket.assigns.shopping_basket.id == basket.id do
        reload_basket(socket, basket.id)
      else
        reload_basket(socket, basket.id) ||
          blank_basket_fallback(List.first(shopping_baskets), socket.assigns.current_user)
      end

    {:noreply,
     socket
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:shopping_basket, active)
     |> assign(:basket_form, nil)}
  end

  # Both basket form components emit `{:update, basket}` when a date-range import
  # rebuilds a basket; handle either the same way.
  def handle_info({mod, {:update, basket}}, socket)
      when mod in [
             MehungryWeb.ShoppingBasketLive.BasicFormComponent,
             MehungryWeb.ShoppingBasketLive.FormComponent
           ] do
    shopping_baskets = load_baskets(socket.assigns.current_user.id)

    active =
      if socket.assigns.shopping_basket && socket.assigns.shopping_basket.id == basket.id do
        reload_basket(socket, basket.id)
      else
        socket.assigns.shopping_basket
      end

    {:noreply,
     socket
     |> assign(:shopping_baskets, shopping_baskets)
     |> assign(:shopping_basket, active || socket.assigns.shopping_basket)
     |> assign(:processing_basket, %ShoppingBasket{})}
  end

  def handle_info({:perform_search, query}, socket) do
    # The user's own private ingredients, surfaced alongside USDA results. Only
    # rows owned by this user are kept (global local-DB rows stay out of the
    # USDA-centric basket flow).
    user_id = socket.assigns.current_user.id

    custom_results =
      query
      |> Mehungry.Food.IngredientSearch.search([], user_id)
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

  # ──────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp load_baskets(user_id) do
    user_id
    |> Inventory.list_shopping_baskets_for_user()
    |> Enum.sort_by(& &1.updated_at, {:desc, NaiveDateTime})
  end

  # Picks the basket to open on mount: the `?basket_id=` one when it's in the
  # user's own list, else the most-recently-updated (list is already sorted).
  defp select_initial_basket(baskets, id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, _} -> Enum.find(baskets, List.first(baskets), &(&1.id == int_id))
      :error -> List.first(baskets)
    end
  end

  defp select_initial_basket(baskets, _id), do: List.first(baskets)

  # A brand-new user with no baskets gets an empty, unsaved basket so the panel
  # renders its first-run state.
  defp blank_basket_fallback(nil, user) do
    %ShoppingBasket{user_id: user.id, basket_ingredients: [], basket_items: []}
  end

  defp blank_basket_fallback(%ShoppingBasket{} = basket, _user), do: basket

  # Re-reads the active basket + the list from the DB after a mutation, so counts,
  # progress and acquired-sink ordering all reflect the new state.
  defp refresh_active_basket(socket) do
    baskets = load_baskets(socket.assigns.current_user.id)

    active =
      reload_basket(socket, socket.assigns.shopping_basket.id) ||
        socket.assigns.shopping_basket

    socket
    |> assign(:shopping_baskets, baskets)
    |> assign(:shopping_basket, active)
  end

  defp reload_basket(_socket, nil), do: nil

  defp reload_basket(socket, id) do
    Inventory.get_user_shopping_basket(socket.assigns.current_user.id, id)
  end

  # User-scoped basket lookup for an event/param id (nil when not owned).
  defp owned_basket(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, _} -> owned_basket(socket, int_id)
      :error -> nil
    end
  end

  defp owned_basket(socket, id) when is_integer(id) do
    Inventory.get_user_shopping_basket(socket.assigns.current_user.id, id)
  end

  # Finds a basket entry by id within the *active* basket (which is already
  # user-scoped), disambiguating items vs recipe-derived ingredients by `type`.
  defp find_entry(socket, "item", id) do
    Enum.find(socket.assigns.shopping_basket.basket_items, &(to_string(&1.id) == to_string(id)))
  end

  defp find_entry(socket, "ingredient", id) do
    Enum.find(
      socket.assigns.shopping_basket.basket_ingredients,
      &(to_string(&1.id) == to_string(id))
    )
  end

  defp find_entry(_socket, _type, _id), do: nil

  defp get_nutrition_value(food, nutrient_name) do
    Enum.find_value(food["food_nutrients"] || [], fn n ->
      if String.contains?(n.nutrient_name, nutrient_name), do: n.value
    end) || 0
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

  defp parse_quantity(q) when is_binary(q) do
    case Float.parse(q) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_quantity(n) when is_number(n), do: n
  defp parse_quantity(_), do: nil

  # Drops nil values so an edit only updates the fields actually provided.
  defp prune(map), do: for({k, v} <- map, not is_nil(v), into: %{}, do: {k, v})
end
