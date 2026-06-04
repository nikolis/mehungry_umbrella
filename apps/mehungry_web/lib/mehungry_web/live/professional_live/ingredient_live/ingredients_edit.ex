defmodule MehungryWeb.ProfessionalLive.IngredientsEdit do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Languages

  def mount(%{"id" => id}, _session, socket) do
    ingredient =
      Food.get_ingredient!(id)
      |> Mehungry.Repo.preload([
        :ingredient_portions,
        :ingredient_translation,
        :ingredient_nutrients
      ])

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
      measurement_units={@measurement_units}
      languages={@languages}
      nutrients={@nutrients}
    />
    """
  end

  def handle_event("validate", %{"ingredient" => params}, socket) do
    changeset =
      socket.assigns.ingredient
      |> Food.change_ingredient(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"ingredient" => params}, socket) do
    handle_action(socket, params)
  end

  # Add new portion
  def handle_event("add_portion", _, socket) do
    portions =
      socket.assigns.form.source.data.ingredient_portions ++ [%{}]

    changeset =
      Ecto.Changeset.put_assoc(
        socket.assigns.form.source,
        :ingredient_portions,
        portions
      )

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  # Add new translation
  def handle_event("add_translation", _, socket) do
    translations =
      socket.assigns.form.source.data.ingredient_translation ++ [%{}]

    changeset =
      Ecto.Changeset.put_assoc(
        socket.assigns.form.source,
        :ingredient_translation,
        translations
      )

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  defp handle_action(socket, params) do
    case params["_action"] do
      "add_portion" ->
        add_portion(socket, params)

      "add_nutrient" ->
        add_nutrient(socket, params)

      "remove_portion:" <> index ->
        remove_portion(socket, params, index)

      _ ->
        case Food.update_ingredient(socket.assigns.ingredient, params) do
          {:ok, _ingredient} ->
            {:noreply,
             socket
             |> put_flash(:info, "Updated successfully")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  defp add_portion(socket, params) do
    portions = Map.get(params, "ingredient_portions", %{})
    new_key = "#{map_size(portions)}"
    updated = Map.put(portions, new_key, %{})
    rebuild_form(socket, Map.put(params, "ingredient_portions", updated))
  end

  defp add_nutrient(socket, params) do
    nutrients = Map.get(params, "ingredient_nutrients", %{})
    new_key = "#{map_size(nutrients)}"
    updated = Map.put(nutrients, new_key, %{})
    rebuild_form(socket, Map.put(params, "ingredient_nutrients", updated))
  end

  defp remove_portion(socket, params, index) do
    portions =
      Map.get(params, "ingredient_portions", %{})
      |> Map.delete(index)

    rebuild_form(socket, Map.put(params, "ingredient_portions", portions))
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.ingredient
      |> Food.change_ingredient(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
