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
        grammar = Mehungry.Food.get_measurement_unit_by_name("grammar")

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
      <div class="grid grid-cols-10 sm:grid-cols-9 gap-2 md:gap-6 display-none">
        <div class=" col-span-4 sm:col-span-3 h-full">
          <.live_component
            module={MehungryWeb.SelectComponentDeep}
            form={@ingredient_form}
            item_function={&Mehungry.Food.search_ingredient_alt/1}
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
        <div class=" col-span-2 my-auto">
          <.input field={@ingredient_form[:quantity]} type="number_subscript" label="quantity"/>
        </div>

        <div class="col-span-3 my-auto">
          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
            form={@ingredient_form}
            id={"measurement_unit_search_componentasdf" <> Integer.to_string(@ingredient_form.index)}
            input_variable={:measurement_unit_id}
          />
        </div>

        <button
          class="text-3xl font-bold col-span-1 "
          name="recipe[_action]"
          value={"remove_ingredient:#{@ingredient_form.index}"}
        >
          ❌
        </button>
      </div>
    </div>
    """
  end

  def get_measurement_unit(nil, assigns), do: assigns.measurement_units

  def get_measurement_unit(ing_val, assigns) when is_binary(ing_val),
    do: assigns.measurement_units ++ get_measurement_unit(ing_val)

  def get_measurement_unit(ing_val, assigns) when is_integer(ing_val),
    do: assigns.measurement_units ++ get_measurement_unit(ing_val)

  def get_measurment_unit("", assigns), do: assigns.measurement_units

  def get_measurement_unit(ing_val, assigns) do
    ing_val = String.to_integer(ing_val)
    assigns.measurement_units ++ get_measurement_unit(ing_val)
  end

  defp get_measurement_unit(nil) do
    []
  end

  defp get_measurement_unit(ing_val) do
    Mehungry.Food.get_measurement_unit_portions_for_ingredient(ing_val)
    |> Enum.map(fn x -> x.measurement_unit end)
    |> Enum.filter(fn x -> !is_nil(x) end)
  end
end
