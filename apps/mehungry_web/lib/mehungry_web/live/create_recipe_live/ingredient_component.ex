defmodule MehungryWeb.IngredientComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <.inputs_for :let={ingredient_form} field={@f[:recipe_ingredients]}>
        <div class="grid grid-cols-11 sm:grid-cols-6 gap-2 md:gap-6 display-none">
          <.live_component
            module={MehungryWeb.SelectComponentSingle3}
            form={ingredient_form}
            item_function={fn x -> Mehungry.Food.search_ingredient_alt(x) end}
            get_by_id_func={fn x -> Mehungry.Food.get_ingredient!(x) end}
            input_variable="ingredient_id"
            id={"ingredient_search_component" <> Integer.to_string(ingredient_form.index)}
          />

          <div class="field input-form col-span-2 sm:col-span-1">
            <.input field={ingredient_form[:quantity]} type="number" />
          </div>

          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
            form={ingredient_form}
            id={"measurement_unit_search_component" <> Integer.to_string(ingredient_form.index)}
            input_variable={:measurement_unit_id}
          />
          <button
            class="text-4xl font-bold "
            name="recipe[_action]"
            value={"remove_ingredient:#{ingredient_form.index}"}
          >
            ❌
          </button>
        </div>
      </.inputs_for>
      <button
        name="recipe[_action]"
        value="add_ingredient"
        class="p-4 font-semibold text-md absolute right-6 text-xl"
      >
        + Add
      </button>
    </div>
    """
  end
end
