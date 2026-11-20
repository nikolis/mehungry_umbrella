defmodule MehungryWeb.ShoppingBasketLive.Index do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents
  use MehungryWeb.Presence, :user_tracking

  alias Phoenix.LiveView.JS

  alias Mehungry.Inventory
  alias Mehungry.Inventory.{ShoppingBasket, BasketItem, BasketIngredient}
  alias Mehungry.FoodData.Usda.SearchClient
  alias MehungryWeb.BasketSharing
  import MehungryWeb.ShoppingBasketLive.Components

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    measurement_units = Mehungry.Food.list_measurement_units()
    change_basket = BasketItem.changeset(%BasketItem{}, %{})

    shopping_baskets = load_baskets(user.id)
    # Deep-link support (?basket_id=): open the requested basket if the user owns
    # it or it is shared with them (e.g. arriving from the calendar's "Shopping
    # list" button, or from accepting an invitation); otherwise fall back to the
    # most-recently-updated one.
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
     |> assign(:id, "add-item-modal")
     # Sharing: the open Share modal (nil | %{link:, pending:}) and the
     # invitations other people addressed to this user.
     |> assign(:share, nil)
     |> assign(:my_invitations, Inventory.list_basket_invitations_for_user(user.id))
     |> assign(:subscribed, MapSet.new())
     |> sync_subscriptions()}
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
    case accessible_basket(socket, id) do
      nil -> {:noreply, socket}
      basket -> {:noreply, assign(socket, shopping_basket: basket, editing_item: nil)}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Sharing (invite / revoke / remove / leave / answer an invitation)
  # ──────────────────────────────────────────────────────────────────────────

  def handle_event("open_share", _params, socket) do
    case socket.assigns.shopping_basket do
      %ShoppingBasket{id: id} when not is_nil(id) ->
        {:noreply, assign(socket, :share, %{link: nil, pending: pending_invitations(socket)})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_share", _params, socket) do
    {:noreply, assign(socket, :share, nil)}
  end

  # One form for both paths: with an email the invitation is also emailed (and,
  # for an existing account, shown in-app); blank creates a link to pass on.
  def handle_event("send_invite", params, socket) do
    email = params |> Map.get("email", "") |> String.trim()
    basket = socket.assigns.shopping_basket
    locale = Gettext.get_locale(MehungryWeb.Gettext)

    case BasketSharing.invite(socket.assigns.current_user, basket.id, email, locale) do
      {:ok, _invitation, url} ->
        message =
          if email == "",
            do: gettext("Invitation link created"),
            else: gettext("Invitation sent")

        {:noreply,
         socket
         |> assign(:share, %{link: url, pending: pending_invitations(socket)})
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, BasketSharing.error_message(reason))}
    end
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    with {int_id, _} <- Integer.parse(id) do
      Inventory.revoke_basket_invitation(
        socket.assigns.current_user,
        socket.assigns.shopping_basket.id,
        int_id
      )
    end

    {:noreply, refresh_share(socket)}
  end

  def handle_event("remove_member", %{"user-id" => user_id}, socket) do
    with {int_id, _} <- Integer.parse(user_id),
         %ShoppingBasket{} = basket <- owned_basket(socket, socket.assigns.shopping_basket.id) do
      Inventory.remove_basket_member(socket.assigns.current_user, basket.id, int_id)
    end

    {:noreply, socket |> refresh_active_basket() |> refresh_share()}
  end

  def handle_event("leave_basket", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with {int_id, _} <- Integer.parse(id),
         :ok <- Inventory.remove_basket_member(user, int_id, user.id) do
      {:noreply,
       socket
       |> assign(share: nil, editing_item: nil)
       |> refresh_active_basket()
       |> put_flash(:info, gettext("You left the list"))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("accept_invitation", %{"id" => id}, socket) do
    with {int_id, _} <- Integer.parse(id),
         {:ok, basket} <-
           Inventory.accept_basket_invitation(socket.assigns.current_user, int_id) do
      {:noreply,
       socket
       |> assign(:shopping_basket, %ShoppingBasket{id: basket.id})
       |> refresh_active_basket()
       |> refresh_my_invitations()
       |> put_flash(:info, gettext("You joined “%{title}”", title: basket.title))}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> refresh_my_invitations()
         |> put_flash(:error, BasketSharing.error_message(reason))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("decline_invitation", %{"id" => id}, socket) do
    with {int_id, _} <- Integer.parse(id) do
      Inventory.decline_basket_invitation(socket.assigns.current_user, int_id)
    end

    {:noreply, refresh_my_invitations(socket)}
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
      {:ok, food} ->
        {:noreply, assign(socket, selected_usda_item: food)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not load that item"))}
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
      usda_fdc_id: selected["fdcId"],
      added_by_id: socket.assigns.current_user.id
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
      usda_fdc_id: nil,
      added_by_id: socket.assigns.current_user.id
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
        # Set the state the person asked for (the opposite of what they were
        # looking at) rather than flipping the stored value, so two people
        # ticking the same line agree. A line someone just deleted is a no-op.
        Inventory.set_acquired(entry, not entry.in_storage, socket.assigns.current_user.id)
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
          Inventory.update_basket_item(
            item,
            prune(%{quantity: quantity, name: params["name"]}),
            socket.assigns.current_user.id
          )

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
        {:noreply,
         socket
         |> assign(:editing_item, nil)
         |> refresh_active_basket()
         |> put_flash(:error, gettext("Could not update the item"))}
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
     |> assign(:basket_form, nil)
     |> sync_subscriptions()}
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

  # A shared list changed (or was deleted) from another session — someone else's
  # browser or phone, or this user's own second tab. Re-read it; if this user no
  # longer has access to the list on screen, fall back to another and say so.
  def handle_info({event, basket_id}, socket) when event in [:basket_changed, :basket_deleted] do
    active_id = socket.assigns.shopping_basket.id
    socket = socket |> refresh_active_basket() |> refresh_share()

    if active_id == basket_id and socket.assigns.shopping_basket.id != basket_id do
      {:noreply,
       socket
       |> assign(share: nil, editing_item: nil)
       |> put_flash(:info, gettext("That list is no longer available"))}
    else
      {:noreply, socket}
    end
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

  # Anything else delivered to this process (it holds PubSub subscriptions, and
  # in tests the mail adapter echoes sent emails to the caller) is ignored
  # rather than crashing the view.
  def handle_info(_message, socket), do: {:noreply, socket}

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
    %ShoppingBasket{user_id: user.id, basket_ingredients: [], basket_items: [], members: []}
  end

  defp blank_basket_fallback(%ShoppingBasket{} = basket, _user), do: basket

  # Re-reads the active basket + the list from the DB after a mutation, so counts,
  # progress and acquired-sink ordering all reflect the new state. When the
  # active basket is gone (deleted, or this user was removed from it) it falls
  # back to another list rather than keeping a stale copy on screen.
  defp refresh_active_basket(socket) do
    baskets = load_baskets(socket.assigns.current_user.id)
    current = socket.assigns.shopping_basket

    active =
      case current.id && reload_basket(socket, current.id) do
        %ShoppingBasket{} = reloaded -> reloaded
        _ -> blank_basket_fallback(List.first(baskets), socket.assigns.current_user)
      end

    socket
    |> assign(:shopping_baskets, baskets)
    |> assign(:shopping_basket, active)
    |> sync_subscriptions()
  end

  defp reload_basket(_socket, nil), do: nil

  defp reload_basket(socket, id) do
    Inventory.get_accessible_basket(socket.assigns.current_user.id, id)
  end

  # Subscribes (once each) to the change topic of every list this user can see,
  # so the sidebar's counts and the open list both follow other people's edits.
  defp sync_subscriptions(socket) do
    if connected?(socket) do
      ids = MapSet.new(socket.assigns.shopping_baskets, & &1.id)
      Enum.each(MapSet.difference(ids, socket.assigns.subscribed), &Inventory.subscribe/1)
      assign(socket, :subscribed, MapSet.union(socket.assigns.subscribed, ids))
    else
      socket
    end
  end

  # Keeps an open Share modal's pending-invitation list current.
  defp refresh_share(%{assigns: %{share: nil}} = socket), do: socket

  defp refresh_share(socket) do
    assign(socket, :share, %{socket.assigns.share | pending: pending_invitations(socket)})
  end

  # Pending invitations are the owner's business only.
  defp pending_invitations(socket) do
    basket = socket.assigns.shopping_basket

    if basket.id && basket.user_id == socket.assigns.current_user.id,
      do: Inventory.list_pending_basket_invitations(basket.id),
      else: []
  end

  defp refresh_my_invitations(socket) do
    assign(
      socket,
      :my_invitations,
      Inventory.list_basket_invitations_for_user(socket.assigns.current_user.id)
    )
  end

  # Basket lookup for reading / item-level changes: owned or shared with the user.
  defp accessible_basket(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, _} -> accessible_basket(socket, int_id)
      :error -> nil
    end
  end

  defp accessible_basket(socket, id) when is_integer(id) do
    Inventory.get_accessible_basket(socket.assigns.current_user.id, id)
  end

  # Owner-scoped basket lookup for list-level changes (rename, delete, rebuild
  # from the calendar, sharing): nil unless this user owns it.
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
