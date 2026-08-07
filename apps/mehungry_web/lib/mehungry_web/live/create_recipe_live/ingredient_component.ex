defmodule MehungryWeb.IngredientComponent do
  use MehungryWeb, :live_component

  @impl true
  def update(%{new_ingredient_id: ingredient_id} = _assigns, socket) do
    gram = Mehungry.Food.get_measurement_unit_by_name("gram")

    measurement_units =
      Mehungry.Food.get_measurement_unit_portions_for_ingredient(ingredient_id)
      |> Enum.map(fn x -> x.measurement_unit end)
      |> Enum.filter(fn x -> !is_nil(x) end)

    socket =
      socket
      |> assign(:measurement_units, measurement_units ++ gram)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_search_fns()

    gram = Mehungry.Food.get_measurement_unit_by_name("gram")

    measurement_units =
      if(!is_nil(socket.assigns.ingredient_form[:ingredient_id].value)) do
        id = socket.assigns.ingredient_form[:ingredient_id].value

        Mehungry.Food.get_measurement_unit_portions_for_ingredient(id)
        |> Enum.map(fn x -> x.measurement_unit end)
        |> Enum.filter(fn x -> !is_nil(x) end)
      else
        []
      end

    measurement_units = measurement_units ++ gram

    socket = assign(socket, :measurement_units, measurement_units)

    {:ok, socket}
  end

  def get_measurement_units() do
  end

  defp assign_search_fns(socket) do
    language = Map.get(socket.assigns, :search_language, "en")
    owner_id = Map.get(socket.assigns, :current_user_id)

    {item_fn, label_fn, get_by_id_fn} =
      if language == "el" do
        item_fn = fn term ->
          Mehungry.Food.IngredientSearch.search_in_language(term, "el", owner_id)
        end

        get_by_id_fn = fn id ->
          ingredient = Mehungry.Food.get_ingredient!(id)

          case Mehungry.Food.find_ingredient_translation("el", id) do
            [greek_name | _] -> %{ingredient | name: greek_name}
            [] -> ingredient
          end
        end

        {item_fn, fn item -> item.name end, get_by_id_fn}
      else
        {
          fn term -> Mehungry.Food.IngredientSearch.search(term, [], owner_id) end,
          fn item -> Mehungry.Utils.remove_parenthesis(item.name) end,
          &Mehungry.Food.get_ingredient!/1
        }
      end

    condition_ids = ingredient_condition_ids(owner_id)
    flags_fn = fn ids -> MehungryWeb.RecipeFlags.flags_for_ingredient_ids(ids, condition_ids) end

    socket
    |> assign(:ingredient_item_fn, item_fn)
    |> assign(:ingredient_label_fn, label_fn)
    |> assign(:ingredient_get_by_id_fn, get_by_id_fn)
    |> assign(:ingredient_flags_fn, flags_fn)
  end

  # The viewer's opted-in health-condition ids, for ingredient badges. `[]` when
  # logged-out or not opted-in, so the picker renders no badges.
  defp ingredient_condition_ids(nil), do: []

  defp ingredient_condition_ids(user_id) do
    user_id
    |> Mehungry.Accounts.get_user_profile_by_user_id()
    |> MehungryWeb.RecipeFlags.opted_in_condition_ids()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-2">
      <%!-- Mobile: two-row stacked layout. Desktop: single-row 10-col grid via md:contents --%>
      <div class="flex flex-col gap-2 md:grid md:grid-cols-10 md:gap-4 md:items-center">
        <%!-- Row 1 on mobile: ingredient selector + delete button --%>
        <div class="flex items-center gap-2 md:contents">
          <div class="flex-1 min-w-0 md:col-span-4 h-full">
            <.live_component
              module={MehungryWeb.SelectComponentDeep}
              form={@ingredient_form}
              item_function={@ingredient_item_fn}
              flags_function={@ingredient_flags_fn}
              get_by_id_func={@ingredient_get_by_id_fn}
              input_variable="ingredient_id"
              label_function={@ingredient_label_fn}
              placeholder="Select an ingredient..."
              modal_title="Search Ingredients"
              parent_id={@id}
              select_function={fn x -> send(self(), {:select_id, x, @id}) end}
              id={"ingredient_search_component" <> Integer.to_string(@ingredient_form.index)}
            />
          </div>
          <button
            class="shrink-0 text-xl font-bold text-red-500/70 hover:text-red-400 transition-colors md:hidden"
            name="recipe[_action]"
            value={"remove_ingredient:#{@ingredient_form.index}"}
          >
            ❌
          </button>
        </div>

        <%!-- Row 2 on mobile: quantity + unit + desktop-only delete --%>
        <div class="flex items-center gap-2 md:contents">
          <div class="w-20 shrink-0 md:col-span-2">
            <.input field={@ingredient_form[:quantity]} type="number_subscript" label="quantity" />
          </div>
          <div class="flex-1 md:col-span-3">
            <.live_component
              module={MehungryWeb.SelectComponent}
              items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
              form={@ingredient_form}
              id={"measurement_unit_search_componentasdf" <> Integer.to_string(@ingredient_form.index)}
              input_variable={:measurement_unit_id}
            />
          </div>
          <button
            class="hidden md:block text-xl font-bold text-red-500/70 hover:text-red-400 transition-colors md:col-span-1"
            name="recipe[_action]"
            value={"remove_ingredient:#{@ingredient_form.index}"}
          >
            ❌
          </button>
        </div>
      </div>
    </div>
    """
  end

  def get_measurement_unit(nil, assigns), do: assigns.measurement_units

  def get_measurement_unit(ing_val, assigns) when is_binary(ing_val),
    do: assigns.measurement_units ++ get_measurement_unit(ing_val)

  def get_measurement_unit(ing_val, assigns) when is_integer(ing_val),
    do: assigns.measurement_units ++ get_measurement_unit(ing_val)

  def get_measurement_unit(ing_val, assigns) do
    ing_val = String.to_integer(ing_val)
    assigns.measurement_units ++ get_measurement_unit(ing_val)
  end

  def get_measurment_unit("", assigns), do: assigns.measurement_units

  defp get_measurement_unit(nil) do
    []
  end

  defp get_measurement_unit(ing_val) do
    Mehungry.Food.get_measurement_unit_portions_for_ingredient(ing_val)
    |> Enum.map(fn x -> x.measurement_unit end)
    |> Enum.filter(fn x -> !is_nil(x) end)
  end
end
