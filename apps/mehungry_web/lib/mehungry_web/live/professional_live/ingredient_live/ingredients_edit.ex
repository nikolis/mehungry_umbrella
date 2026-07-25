defmodule MehungryWeb.ProfessionalLive.IngredientsEdit do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Languages

  # The taxonomy whose placement is editable from this form (same tree reviewed
  # at /professional/taxonomy/review).
  @taxonomy_slug "bio-nutritional"

  def mount(%{"id" => id}, _session, socket) do
    ingredient =
      Food.get_ingredient!(id)
      |> Mehungry.Repo.preload([
        :ingredient_portions,
        :ingredient_translation,
        :ingredient_nutrients
      ])

    changeset = Food.change_ingredient(ingredient)
    taxonomy = Food.get_taxonomy_by_slug(@taxonomy_slug)

    {:ok,
     socket
     |> assign(:form_params, %{})
     |> assign(:categories, Food.list_categories())
     |> assign(:measurement_units, Food.list_measurement_units())
     |> assign(:nutrients, Food.list_nutrients())
     |> assign(:languages, Languages.list_languages())
     |> assign(:ingredient, ingredient)
     |> assign(:taxonomy, taxonomy)
     |> assign(:taxonomy_leaf_options, taxonomy_leaf_options(taxonomy))
     |> assign(:taxonomy_node_id, current_taxonomy_node_id(taxonomy, ingredient))
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
      taxonomy={@taxonomy}
      taxonomy_leaf_options={@taxonomy_leaf_options}
      taxonomy_node_id={@taxonomy_node_id}
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
          {:ok, ingredient} ->
            node_id = save_taxonomy_node(socket, ingredient, params)

            {:noreply,
             socket
             |> assign(:taxonomy_node_id, node_id)
             |> put_flash(:info, "Updated successfully")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  # Persists the taxonomy placement chosen in the form (a plain
  # `ingredient[taxonomy_node_id]` select that the ingredient changeset ignores).
  # Returns the node id now assigned so the form can reflect it.
  defp save_taxonomy_node(%{assigns: %{taxonomy: nil}}, _ingredient, _params), do: nil

  defp save_taxonomy_node(%{assigns: %{taxonomy: taxonomy}}, ingredient, params) do
    node_id = params["taxonomy_node_id"]
    Food.set_ingredient_node(taxonomy.id, ingredient.id, node_id)
    if node_id in [nil, ""], do: nil, else: String.to_integer(node_id)
  end

  defp taxonomy_leaf_options(nil), do: []

  defp taxonomy_leaf_options(taxonomy) do
    taxonomy.id
    |> Food.list_leaves_with_paths()
    |> Enum.map(&{&1.path, &1.id})
  end

  defp current_taxonomy_node_id(nil, _ingredient), do: nil

  defp current_taxonomy_node_id(taxonomy, ingredient) do
    Food.get_ingredient_node_id(taxonomy.id, ingredient.id)
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
