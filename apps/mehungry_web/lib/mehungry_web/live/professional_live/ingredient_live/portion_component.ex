defmodule MehungryWeb.Professional.PortionsComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-display font-medium text-parchment">Portions</h3>
        <button
          type="submit"
          name="ingredient[_action]"
          value="add_portion"
          class="flex items-center gap-1 px-3 py-1.5 rounded-full border border-ink-panel2 text-parchment-dim hover:bg-ink-panel2 hover:text-parchment text-xs font-semibold transition-colors"
        >
          + Add Portion
        </button>
      </div>
      <p class="text-xs text-parchment-dim mb-3">
        A portion needs a gram weight and <span class="text-parchment">either</span>
        a measurement unit <span class="text-parchment">or</span>
        a free-text name (e.g. "1 medium banana", "1 slice").
      </p>
      <div class="space-y-3">
        <.inputs_for :let={portion_form} field={@form[:ingredient_portions]}>
          <div class="bg-black/20 border border-ink-panel2 rounded-xl p-3 flex flex-col sm:flex-row sm:items-end gap-3">
            <input
              type="hidden"
              name="ingredient[ingredient_portions_sort][]"
              value={portion_form.index}
            />
            <div class="flex-1">
              <.input
                type="text"
                label="Portion name (optional)"
                placeholder="e.g. 1 medium banana"
                name={portion_form[:description].name}
                value={portion_form[:description].value}
              />
            </div>
            <div class="flex-1">
              <label class="block text-sm font-semibold text-parchment-dim mb-1">
                Measurement unit (optional)
              </label>
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
