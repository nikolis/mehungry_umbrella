defmodule MehungryWeb.Professional.IngredientFormComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <form phx-change="validate" phx-submit="save" class="max-w-5xl mx-auto  relative">
      <div class="bg-white shadow-md rounded-lg pb-24 p-4 space-y-6 ">
        <.back navigate={~p"/professional/ingredients"}>Back</.back>

        <h2 class="text-xl font-semibold mb-4">Ingredient Details</h2>
        <div class="flex flex-row  ">
          <.input
            type="text"
            class=""
            label="Name"
            name="ingredient[name]"
            value={@form[:name].value}
          />
          <input type="hidden" name="ingredient[_action]" value="" />
          <input type="hidden" name="ingredient[food_class]" value={@form[:food_class].value} />
          
    <!-- CATEGORY DROPDOWN -->
          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@categories, fn x -> {Integer.to_string(x.id), x.name} end)}
            form={@form}
            id="category_select_component"
            input_variable={:category_id}
          />
          
    <!-- MEASUREMENT UNIT DROPDOWN -->

          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
            form={@form}
            id="measurement_unit_select_component_ingredient"
            input_variable={:measurement_unit_id}
          />
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
        <.button type="submit">Save</.button>
      </div>
    </form>
    """
  end

  def handle_event("validate", %{"ingredient" => params}, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"ingredient" => params}, socket) do
    send(self(), {:save, params})
    {:noreply, socket}
  end
end
