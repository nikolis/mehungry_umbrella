defmodule MehungryWeb.Professional.NutrientComponent do
  use MehungryWeb, :live_component

  def get_measurement_unit_for_nutrient(id) do
    if is_nil(id) do
      ""
    else
      nutrient = Mehungry.Food.get_nutrient(id)

      if is_nil(nutrient) do
        ""
      else
        nutrient.measurement_unit.name
      end
    end
  end

  def render(assigns) do
    ~H"""
    <div class="relative  p-8">
      <h3 class="m-auto w-wrap text-2xl font-semibold mb-2">Nutrients</h3>
      <.inputs_for :let={nutrients_form} field={@form[:ingredient_nutrients]}>
        <div class="grid grid-cols-5  relative py-2">
          <input
            type="hidden"
            name="ingredient[ingredient_nutrients_sort][]"
            value={nutrients_form.index}
          />

          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@nutrients, fn x -> {Integer.to_string(x.id), x.name} end)}
            form={nutrients_form}
            id={"measurement_unit_select_component_ingredient" <> Integer.to_string(nutrients_form.index)}
            input_variable={:nutrient_id}
            item_function={fn x -> x.name end}
          />

          <.input
            type="number_subscript"
            label="Amount per 100gram"
            subscript={get_measurement_unit_for_nutrient(nutrients_form[:nutrient_id].value)}
            name={nutrients_form[:amount].name}
            value={nutrients_form[:amount].value}
          >
            <div>
              {get_measurement_unit_for_nutrient(nutrients_form[:nutrient_id].value)}
            </div>
          </.input>

          <button name="ingredient[_action]" value={"remove_nutrient:#{nutrients_form.index}"}>
            ❌
          </button>
        </div>
      </.inputs_for>
      <button
        name="ingredient[_action]"
        value="add_nutrient"
        class="px-4 font-semibold text-md absolute right-10"
      >
        Add Nutrient
      </button>
    </div>
    """
  end
end
