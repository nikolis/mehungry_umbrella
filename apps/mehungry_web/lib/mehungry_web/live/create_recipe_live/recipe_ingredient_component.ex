defmodule MehungryWeb.CreateRecipeLive.RecipeIngredientComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Food
  alias Mehungry.Food.RecipeIngredient

  defmodule IngredientEntry do
    defstruct [:ingredient_id, :measurement_unit_id, :quantity]
  end

  @ingredient_entry_types %{
    ingredient_id: :integer,
    measurement_unit_id: :integer,
    quantity: :float
  }

  def change_ingredient_entry(ingredient_entry, attrs) do
    {ingredient_entry, @ingredient_entry_types}
    |> Ecto.Changeset.cast(attrs, Map.keys(@ingredient_entry_types))
    |> Ecto.Changeset.validate_number(:quantity, greater_than: 0)
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{recipe_ingredient: recipe_ingredient} = assigns, socket) do
    changeset = Food.change_recipe_ingredient(recipe_ingredient)
    ingredients = Food.list_ingredients()
    measurement_units = Food.list_measurement_units()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ingredients, ingredients)
     |> assign(:ingredient, nil)
     |> assign(:measurement_units, measurement_units)
     |> assign(:changeset, changeset)
     |> assign(:temp_id, recipe_ingredient["temp_id"])}

    # |> assign(:recipe_ingredient, recipe_ingredient)}
  end

  @impl true
  def handle_event("validate", %{"recipe_ingredient" => recipe_ingredient_params}, socket) do
    changeset = validate_recipe_ingredient(%RecipeIngredient{}, recipe_ingredient_params)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp validate_recipe_ingredient(rec_ingredient, recipe_ingredient_params) do
    rec_ingredient
    |> Food.change_recipe_ingredient(recipe_ingredient_params)
    |> Map.put(:action, :validate)
  end

  def handle_event("mu_selected", %{"mu_id" => mu_id}, socket) do
    recipe_ingredient_ch = socket.assigns.changeset
    mu_id = String.to_integer(mu_id)
    params = socket.assigns.changeset.changes
    params = Map.put(params, :measurement_unit_id, mu_id)
    handle_event("validate", %{"recipe_ingredient" => params}, socket)
  end

  def handle_event("ingredient_selected", %{"ingredient_id" => ingr_id}, socket) do
    recipe_ingredient_ch = socket.assigns.changeset
    ingredient_id = String.to_integer(ingr_id)
    params = socket.assigns.changeset.changes
    params = Map.put(params, :ingredient_id, ingr_id)
    handle_event("validate", %{"recipe_ingredient" => params}, socket)
  end

  def handle_event("save", %{"recipe_ingredient" => recipe_ingredient_params}, socket) do
    recipe_ingredient_params =
      Map.put(recipe_ingredient_params, "temp_id", socket.assigns.temp_id)

    send(socket.root_pid, {:recipe_ingredient, recipe_ingredient_params})
    {:noreply, push_patch(socket, to: socket.assigns.return_to)}
  end

  defp save_recipe_ingredient(socket, :edit, recipe_ingredient_params) do
    case Food.update_recipe_ingredient(socket.assigns.recipe_ingredient, recipe_ingredient_params) do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe Ingredient updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_recipe_ingredient(socket, :new, recipe_ingredient_params) do
    case Food.create_recipe_ingredient(recipe_ingredient_params) do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
