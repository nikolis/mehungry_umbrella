defmodule MehungryWeb.ProfessionalLive.IngredientsCreate do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientPortion, IngredientNutrient}
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

  # `validate` must never persist — it only refreshes the in-memory changeset
  # so inline errors show as the admin types.
  def handle_event("validate", %{"ingredient" => params}, socket) do
    rebuild_form(socket, params)
  end

  # Row add/remove for the nested sub-forms is driven through cast_assoc's
  # `sort_param`/`drop_param` (see `Ingredient.changeset`); anything else is the
  # real create. Mirrors `ProfessionalLive.IngredientsEdit`.
  defp handle_action(socket, params) do
    case params["_action"] do
      "add_portion" ->
        rebuild_form(socket, add_row(params, "ingredient_portions"))

      "add_nutrient" ->
        rebuild_form(socket, add_row(params, "ingredient_nutrients"))

      "add_ingredient_translation" ->
        rebuild_form(socket, add_row(params, "ingredient_translation"))

      "remove_portion:" <> index ->
        rebuild_form(socket, drop_row(params, "ingredient_portions", index))

      "remove_nutrient:" <> index ->
        rebuild_form(socket, drop_row(params, "ingredient_nutrients", index))

      "remove_ingredient_translation:" <> index ->
        rebuild_form(socket, drop_row(params, "ingredient_translation", index))

      _ ->
        case Food.create_ingredient(params) do
          {:ok, _ingredient} ->
            {:noreply,
             socket
             |> put_flash(:info, "Saved successfully")
             |> push_navigate(to: ~p"/professional/ingredients")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  # Append a sentinel to `<field>_sort` so cast_assoc adds one new empty child.
  defp add_row(params, field) do
    Map.update(params, "#{field}_sort", ["new"], &(&1 ++ ["new"]))
  end

  # Append the row index to `<field>_drop` so cast_assoc drops that child.
  defp drop_row(params, field, index) do
    Map.update(params, "#{field}_drop", [index], &(&1 ++ [index]))
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.ingredient
      |> Food.change_ingredient(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
