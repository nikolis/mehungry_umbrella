defmodule MehungryWeb.Professional.IngredientFormComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <form
      phx-change="validate"
      phx-submit="save"
      class="px-4 py-6 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-6"
    >
      <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6">
        <div class="flex items-center justify-between mb-6">
          <.back navigate={~p"/professional/ingredients"}>Back</.back>
          <h2 class="text-lg font-semibold text-white">Ingredient Details</h2>
        </div>

        <input type="hidden" name="ingredient[_action]" value="" />
        <input type="hidden" name="ingredient[food_class]" value={@form[:food_class].value} />

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-1">
              Name
            </label>
            <.input
              type="text"
              name="ingredient[name]"
              value={@form[:name].value}
            />
          </div>
          <div>
            <label class="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-1">
              FDC ID
            </label>
            <.input
              type="number"
              name="ingredient[fdc_id]"
              value={@form[:fdc_id].value}
            />
          </div>
          <div>
            <label class="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-1">
              Category
            </label>
            <.live_component
              module={MehungryWeb.SelectComponent}
              items={Enum.map(@categories, fn x -> {Integer.to_string(x.id), x.name} end)}
              form={@form}
              id="category_select_component"
              input_variable={:category_id}
            />
          </div>
          <div>
            <label class="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-1">
              Default Measurement Unit
            </label>
            <.live_component
              module={MehungryWeb.SelectComponent}
              items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
              form={@form}
              id="measurement_unit_select_component_ingredient"
              input_variable={:measurement_unit_id}
            />
          </div>
        </div>
      </div>

      <.live_component
        module={MehungryWeb.Professional.NutrientComponent}
        id="nutrients"
        form={@form}
        nutrients={@nutrients}
      />

      <.live_component
        module={MehungryWeb.Professional.PortionsComponent}
        id="portions"
        form={@form}
        measurement_units={@measurement_units}
      />

      <.live_component
        module={MehungryWeb.Professional.TranslationsComponent}
        id="translations"
        form={@form}
        languages={@languages}
      />

      <div class="flex justify-end pb-8">
        <button
          type="submit"
          class="px-6 py-3 rounded-full bg-primary-500 hover:bg-primary-600 text-white font-semibold text-sm transition-colors"
        >
          Save Ingredient
        </button>
      </div>
    </form>
    """
  end

  def handle_event("validate", %{"ingredient" => _params}, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"ingredient" => params}, socket) do
    send(self(), {:save, params})
    {:noreply, socket}
  end
end
