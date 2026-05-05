defmodule MehungryWeb.ProfessionalLive.IngredientsCreate do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientPortion, IngredientNutrient, IngredientTranslation}
  alias Mehungry.Languages

  def mount(_, _session, socket) do
    ingredient =
      %Ingredient{
        food_class: "Admin created",
        ingredient_portions: [%IngredientPortion{}],
        ingredient_nutrients: [%IngredientNutrient{}],
        ingredient_translation: []
      }

    changeset = Food.change_ingredient(ingredient)

    {:ok,
     socket
     |> assign(:form_params, %{})
     |> assign(:categories, Food.list_categories())
     |> assign(:measurement_units, Food.list_measurement_units())
     |> assign(:nutrients, Food.list_nutrients())
     |> assign(:languages, Languages.list_languages())
     |> assign(:ingredient, ingredient)
     |> assign(:form, to_form(changeset))}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={MehungryWeb.Professional.IngredientFormComponent}
      id="ingredient-form"
      ingredient={@ingredient}
      form={@form}
      categories={@categories}
      nutrients={@nutrients}
      measurement_units={@measurement_units}
      languages={@languages}
    />
    """
  end

  def handle_event("save", %{"ingredient" => params}, socket) do
    handle_action(socket, params)
  end

  def handle_event("validate", %{"ingredient" => params}, socket) do
    handle_action(socket, params)
  end

  defp handle_action(socket, params) do
    case params["_action"] do
      "add_portion" ->
        add_portion(socket, params)

      "add_nutrient" ->
        add_nutrient(socket, params)

      "add_ingredient_translation" ->
        add_ingredient_translation(socket, params)

      "remove_portion:" <> index ->
        remove_portion(socket, params, index)

      "remove_nutrient:" <> index ->
        remove_nutrient(socket, params, index)

      _ ->
        case Food.create_ingredient(params) do
          {:ok, _ingredient} ->
            {:noreply,
             socket
             |> put_flash(:info, "Saved successfully")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  defp add_portion(socket, params) do
    portions = Map.get(params, "ingredient_portions", %{})

    new_key = "#{map_size(portions)}"

    updated =
      Map.put(portions, new_key, %{})

    new_params =
      Map.put(params, "ingredient_portions", updated)

    rebuild_form(socket, new_params)
  end

  defp add_ingredient_translation(socket, params) do
    nutrients = Map.get(params, "ingredient_translation", %{})

    new_key = "#{map_size(nutrients)}"

    updated =
      Map.put(nutrients, new_key, %{})

    new_params =
      Map.put(params, "ingredient_translation", updated)

    rebuild_form(socket, new_params)
  end

  defp add_nutrient(socket, params) do
    nutrients = Map.get(params, "ingredient_nutrients", %{})

    new_key = "#{map_size(nutrients)}"

    updated =
      Map.put(nutrients, new_key, %{})

    new_params =
      Map.put(params, "ingredient_nutrients", updated)

    rebuild_form(socket, new_params)
  end

  defp remove_portion(socket, params, index) do
    portions =
      Map.get(params, "ingredient_portions", %{})
      |> Map.delete(index)

    new_params =
      Map.put(params, "ingredient_portions", portions)

    rebuild_form(socket, new_params)
  end

  defp remove_nutrient(socket, params, index) do

    portions =
      Map.get(params, "ingredient_nutrients", %{})
      |> Map.delete(index)

    new_params =
      Map.put(params, "ingredient_nutrients", portions)

    rebuild_form(socket, new_params)
  end

  def handle_info({:save, params}, socket) do
    case Food.update_ingredient(socket.assigns.ingredient, params) do
      {:ok, ingredient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved")
         |> assign(:ingredient, ingredient)}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}
    end
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.ingredient
      |> Food.change_ingredient(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
