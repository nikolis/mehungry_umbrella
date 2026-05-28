defmodule MehungryWeb.Professional.PortionsComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-white">Portions</h3>
        <button
          type="submit"
          name="ingredient[_action]"
          value="add_portion"
          class="flex items-center gap-1 px-3 py-1.5 rounded-full border border-slate-600 text-slate-300 hover:bg-slate-700 text-xs font-semibold transition-colors"
        >
          + Add Portion
        </button>
      </div>
      <div class="space-y-3">
        <.inputs_for :let={portion_form} field={@form[:ingredient_portions]}>
          <div class="bg-slate-700/40 rounded-xl p-3 flex flex-col sm:flex-row sm:items-end gap-3">
            <input
              type="hidden"
              name="ingredient[ingredient_portions_sort][]"
              value={portion_form.index}
            />
            <div class="flex-1">
              <.live_component
                module={MehungryWeb.SelectComponent}
                items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
                form={portion_form}
                id={"measurement_unit_portion_select_id_" <> Integer.to_string(portion_form.index)}
                input_variable={:measurement_unit_id}
              />
            </div>
            <div class="flex-1">
              <.input
                type="number"
                label="Gram weight per unit"
                name={portion_form[:gram_weight].name}
                value={portion_form[:gram_weight].value}
              />
            </div>
            <button
              type="submit"
              name="ingredient[_action]"
              value={"remove_portion:#{portion_form.index}"}
              class="self-end text-slate-500 hover:text-red-400 transition-colors p-1"
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
