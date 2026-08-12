defmodule MehungryWeb.ProfessionalLive.IngredientsEdit do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Languages

  # The taxonomy whose placement is editable from this form (same tree reviewed
  # at /professional/taxonomy/review).
  @taxonomy_slug "bio-nutritional"

  def mount(%{"id" => id}, _session, socket) do
    ingredient = load_ingredient(id)
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

  # The portion/nutrient/translation sub-forms add and remove rows through the
  # `sort_param`/`drop_param` mechanism declared on `Ingredient.changeset`:
  # "add" appends a sentinel to the collection's sort param so cast_assoc
  # materialises a new empty child; "remove" appends the clicked row index to
  # the drop param so cast_assoc drops it (deleting the persisted row via
  # `on_replace: :delete`). Both only rebuild the in-memory form — nothing is
  # persisted until the ingredient itself is saved (the `_` clause).
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
        save_ingredient(socket, params)
    end
  end

  # Collections cast_assoc-ed by `Ingredient.changeset`. When the admin removes
  # the *last* row of one, the form submits no key for it at all, and cast_assoc
  # would then leave the existing children untouched. Injecting an empty map for
  # any missing key makes cast_assoc cast it to `[]` and delete the orphans
  # (via `on_replace: :delete`).
  @collections ~w(ingredient_portions ingredient_nutrients ingredient_translation)

  defp save_ingredient(socket, params) do
    params =
      Enum.reduce(@collections, params, fn key, acc ->
        if Map.has_key?(acc, key), do: acc, else: Map.put(acc, key, %{})
      end)

    case Food.update_ingredient(socket.assigns.ingredient, params) do
      {:ok, ingredient} ->
        node_id = save_taxonomy_node(socket, ingredient, params)
        # Reload with associations so a follow-up edit works against current DB
        # state (e.g. a just-deleted portion is really gone from the struct).
        ingredient = load_ingredient(ingredient.id)

        {:noreply,
         socket
         |> assign(:ingredient, ingredient)
         |> assign(:taxonomy_node_id, node_id)
         |> assign(:form, to_form(Food.change_ingredient(ingredient)))
         |> put_flash(:info, "Updated successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
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

  defp load_ingredient(id) do
    Food.get_ingredient!(id)
    |> Mehungry.Repo.preload([
      :ingredient_portions,
      :ingredient_translation,
      :ingredient_nutrients
    ])
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

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.ingredient
      |> Food.change_ingredient(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
