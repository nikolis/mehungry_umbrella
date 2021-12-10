defmodule MehungryWeb.CreateRecipeLive.RecipeIngredientComponent do
use MehungryWeb, :live_component

alias Mehungry.Food


  defmodule  IngredientEntry do 
    defstruct [:ingredient_id, :measurement_unit_id, :quantity]
  end

  @ingredient_entry_types  %{ingredient_id: :integer, measurement_unit_id: :integer, quantity: :float}

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
    changeset = Food.change_recipe_ingredient(%{})
    ingredients = Food.list_ingredients()
    measurement_units = Food.list_measurement_units() 
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ingredients, ingredients)
     |> assign(:ingredient, nil)
     |> assign(:measurement_units, measurement_units) 
     |> assign(:changeset, changeset)
     |> assign(:recipe_ingredient, recipe_ingredient) 
    }
  end

  @impl true
  def handle_event("validate", %{"recipe_ingredient" => recipe_ingredient_params}, socket) do

    changeset = validate_recipe_ingredient(socket.assigns.recipe_ingredient,recipe_ingredient_params)
    IO.inspect(changeset, label: "Handle validate event") 
    {:noreply, assign(socket, :changeset, changeset)}
  end


  defp validate_recipe_ingredient(rec_ingredient, recipe_ingredient_params) do
     rec_ingredient
     |> Food.change_recipe_ingredient(recipe_ingredient_params)
     |> Map.put(:action, :validate)
  end


  def handle_event("ingredient_selected", %{"ingredient_id" => ingr_id}, socket) do
    #{:noreply, assign(socket, :ingredient, ingredient)}
    recipe_ingredient_ch = socket.assigns.changeset
    ingredient_id = String.to_integer(ingr_id)

    #recipe_ingredient_ch_up =  Ecto.Changeset.put_change(recipe_ingredient_ch, :ingredient_id, ingredient_id) 
    params = %{"ingredient_id" =>  ingredient_id}
    changeset = validate_recipe_ingredient(socket.assigns.recipe_ingredient, params)
    IO.inspect(changeset, label: "evenet select ingredient")
    {:noreply, 
      socket
      |> assign(:changeset, changeset)
    }  
  end

  def handle_event("save", %{"recipe_ingredient" => recipe_ingredient_params}, socket) do
    IO.inspect(recipe_ingredient_params, label: "evenet save recipe_params")
    {:noreply, push_event(socket, "safdfadssdfa", %{points: 100, user: "josé"})}

    #save_recipe_ingredient(socket, socket.assigns.action, recipe_ingredient_params)
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
