defmodule MehungryWeb.RecipeDetailsTabsConfig do
  @moduledoc """
    This is a module Representing the contents of a particular instance of a
    tabs comopnent
  """
  # In Phoenix apps, the line is typically: use MyAppWeb, :html
  use Phoenix.Component

  @doc """
  Returns all the tabs of the tabs_component 
  each element of the list returned here should be handled
  by a tabs_content function to avoid runtime errors
  """
  def get_states() do
    ["Ingredients", "Nutrients", "Steps"]
  end

  def tab_content(%{state: "Ingredients"} = assigns) do
    MehungryWeb.RecipeComponents.recipe_ingredients(assigns.recipe)
  end

  def tab_content(%{state: "Nutrients"} = assigns) do
    MehungryWeb.RecipeComponents.recipe_nutrients(assigns)
  end

  def tab_content(%{state: "Steps"} = assigns) do
    MehungryWeb.RecipeComponents.recipe_steps(assigns.recipe)
  end
end
