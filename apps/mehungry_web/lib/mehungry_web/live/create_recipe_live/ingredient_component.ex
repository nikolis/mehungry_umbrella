defmodule MehungryWeb.IngredientComponent do
  use MehungryWeb, :live_component

  @impl true
  def update(%{new_ingredient_id: ingredient_id} = assigns, socket) do
    grammar = Mehungry.Food.get_measurement_unit_by_name("grammar")

    measurement_units =
      Mehungry.Food.get_measurement_unit_portions_for_ingredient(ingredient_id)
      |> Enum.map(fn x -> x.measurement_unit end)
      |> Enum.filter(fn x -> !is_nil(x) end)

    socket =
      socket
      |> assign(:measurement_units, measurement_units ++ grammar)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)

    grammar = Mehungry.Food.get_measurement_unit_by_name("grammar")

    measurement_units =
      if(!is_nil(socket.assigns.ingredient_form[:ingredient_id].value)) do
        id = socket.assigns.ingredient_form[:ingredient_id].value

        Mehungry.Food.get_measurement_unit_portions_for_ingredient(id)
        |> Enum.map(fn x -> x.measurement_unit end)
        |> Enum.filter(fn x -> !is_nil(x) end)
      else
        []
      end

    measurement_units = measurement_units ++ grammar

    socket = assign(socket, :measurement_units, measurement_units)

    {:ok, socket}
  end

  def get_measurement_units() do
  end

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
              item_function={&Mehungry.Food.IngredientSearch.search/1}
              get_by_id_func={&Mehungry.Food.get_ingredient!/1}
              input_variable="ingredient_id"
              label_function={fn item -> Mehungry.Utils.remove_parenthesis(item.name) end}
              placeholder="Select an ingredient..."
              modal_title="Search Ingredients"
              parent_id={@id}
              select_function={fn x -> send(self(), {:select_id, x, @id}) end}
              id={"ingredient_search_component" <> Integer.to_string(@ingredient_form.index)}
            />
          </div>
          <button
            class="shrink-0 text-2xl font-bold md:hidden"
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
            class="hidden md:block text-2xl font-bold md:col-span-1"
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
