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
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-display font-medium text-parchment">Nutrients</h3>
        <button
          name="ingredient[_action]"
          value="add_nutrient"
          class="flex items-center gap-1 px-3 py-1.5 rounded-full border border-ink-panel2 text-parchment-dim hover:bg-ink-panel2 hover:text-parchment text-xs font-semibold transition-colors"
        >
          + Add Nutrient
        </button>
      </div>
      <div class="space-y-3">
        <.inputs_for :let={nutrients_form} field={@form[:ingredient_nutrients]}>
          <div class="bg-black/20 border border-ink-panel2 rounded-xl p-3 flex flex-col sm:flex-row sm:items-end gap-3">
            <input
              type="hidden"
              name="ingredient[ingredient_nutrients_sort][]"
              value={nutrients_form.index}
            />
            <div class="flex-1">
              <.live_component
                module={MehungryWeb.SelectComponent}
                items={Enum.map(@nutrients, fn x -> {Integer.to_string(x.id), x.name} end)}
                form={nutrients_form}
                id={"measurement_unit_select_component_ingredient" <> Integer.to_string(nutrients_form.index)}
                input_variable={:nutrient_id}
                item_function={fn x -> x.name end}
              />
            </div>
            <div class="flex-1">
              <.input
                type="number_subscript"
                label="Amount per 100g"
                subscript={get_measurement_unit_for_nutrient(nutrients_form[:nutrient_id].value)}
                name={nutrients_form[:amount].name}
                value={nutrients_form[:amount].value}
              >
                <div>{get_measurement_unit_for_nutrient(nutrients_form[:nutrient_id].value)}</div>
              </.input>
            </div>
            <button
              name="ingredient[_action]"
              value={"remove_nutrient:#{nutrients_form.index}"}
              class="self-end text-parchment-dim hover:text-red-400 transition-colors p-1"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
        </.inputs_for>
      </div>
    </div>
    """
  end
end
