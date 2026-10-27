defmodule MehungryWeb.ShoppingBasketLive.FormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Inventory
  alias Mehungry.History

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header class="text-md">
        {@title}
      </.header>
      <span></span>
      <div style="" phx-update="ignore" id="container" phx-hook="DatePicker">
        <input name="endtDate" type="hidden" placeholder="Select Date.." data-input />
      </div>

      <.simple_form
        for={@form}
        id="form-basket"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:start_dt]} type="hidden" />
        <.input field={@form[:end_dt]} type="hidden" label="Intro" />
        <:actions>
          <.button type="primary" phx-disable-with="Saving...">Create Basket</.button>
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
        notify_parent({:saved, shopping_basket})

        {:noreply,
         socket
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_shopping_basket(socket, :import_items, shopping_basket_params) do
    create_basket(socket, shopping_basket_params)
  end

  defp create_basket(socket, basket_params_params) do
    changeset =
      socket.assigns.shopping_basket
      |> Inventory.change_shopping_basket(basket_params_params)
      |> Map.put(:action, :validate)

    case changeset.valid? do
      false ->
        {:noreply, assign_form(socket, changeset)}

      true ->
        with {:ok, st_dt} <- parse_naive(basket_params_params["start_dt"]),
             {:ok, en_dt} <- parse_naive(basket_params_params["end_dt"]) do
          build_basket_from_range(socket, basket_params_params, st_dt, en_dt)
        else
          # A date was never picked (range not completed) — don't crash; ask for one.
          :error ->
            {:noreply,
             socket
             |> put_flash(:error, "Pick a start and end date on the calendar first.")}
        end
    end
  end

  # Parses the hidden-field ISO datetime the DatePicker hook writes; `nil`/blank
  # (incomplete range) yields `:error` so the caller can flash instead of raising.
  defp parse_naive(value) when is_binary(value) and value != "" do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, dt} -> {:ok, dt}
      _ -> :error
    end
  end

  defp parse_naive(_), do: :error

  defp build_basket_from_range(socket, _basket_params_params, st_dt, en_dt) do
    user = socket.assigns.user

    user_meals =
      History.list_history_user_meals_for_user(user.id, st_dt, en_dt)

    all_ingredients = Inventory.aggregate_meal_ingredients(user_meals)

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
     |> push_patch(to: socket.assigns.patch)
     |> assign(:shopping_basket, shopping_basket)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
