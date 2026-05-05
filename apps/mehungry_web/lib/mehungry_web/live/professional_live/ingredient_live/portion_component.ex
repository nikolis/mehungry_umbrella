defmodule MehungryWeb.Professional.PortionsComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="relative px-8">
      <h3 class="text-xl font-semibold mb-2">Portions</h3>
      <.inputs_for :let={portion_form} field={@form[:ingredient_portions]}>
        <div class="flex flex-row p-2">
          <input
            type="hidden"
            name="ingredient[ingredient_portions_sort][]"
            value={portion_form.index}
          />
          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
            form={portion_form}
            id={"measurement_unit_portion_select_id_" <> Integer.to_string(portion_form.index)}
            input_variable={:measurement_unit_id}
          />

          <.input
            type="number"
            label="gram weight per unit"
            name={portion_form[:gram_weight].name}
            value={portion_form[:gram_weight].value}
          />

          <button
            type="submit"
            name="ingredient[_action]"
            value={"remove_portion:#{portion_form.index}"}
          >
            ❌
          </button>
        </div>
      </.inputs_for>
      <button
        type="submit"
        name="ingredient[_action]"
        value="add_portion"
        class="px-4 font-semibold text-md absolute right-10"
      >
        + Add Portion
      </button>
    </div>
    """
  end
end
