defmodule MehungryWeb.IngredientComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <.inputs_for :let={ingredient_form} field={@f[:recipe_ingredients]}>
        <div class="grid grid-cols-9 sm:grid-cols-9 gap-2 md:gap-6 display-none">
          <div class=" col-span-3 sm:col-span-4 h-full">
            <.live_component
              module={MehungryWeb.SelectComponentDeep}
              form={ingredient_form}
              item_function={&Mehungry.Food.search_ingredient_alt/1}
              get_by_id_func={&Mehungry.Food.get_ingredient!/1}
              input_variable="ingredient_id"
              label_function={fn item -> Mehungry.Utils.remove_parenthesis(item.name) end}
              placeholder="Select an ingredient..."
              modal_title="Search Ingredients"
              id={"ingredient_search_component" <> Integer.to_string(ingredient_form.index)}
            />
          </div>
          <div class="field input-form col-span-2 ">
            <.input field={ingredient_form[:quantity]} type="number" />
          </div>

          <div class="col-span-3">
            <.live_component
              module={MehungryWeb.SelectComponent}
              items={Enum.map(@measurement_units, fn x -> {Integer.to_string(x.id), x.name} end)}
              form={ingredient_form}
              id={"measurement_unit_search_componentasdf" <> Integer.to_string(ingredient_form.index)}
              input_variable={:measurement_unit_id}
            />
          </div>

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
