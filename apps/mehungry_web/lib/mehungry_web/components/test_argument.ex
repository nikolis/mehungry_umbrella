defmodule MehungryWeb.TestArgument do
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
    ["ingredients", "nutrients", "steps"]
  end

  def tab_content(%{state: "ingredients"} = assigns) do
    MehungryWeb.CoreComponents.recipe_ingredients(assigns.recipe)
  end

  def tab_content(%{state: "nutrients"} = assigns) do
    MehungryWeb.CoreComponents.recipe_nutrients(assigns)
  end

  def tab_content(%{state: "steps"} = assigns) do
    MehungryWeb.CoreComponents.recipe_steps(assigns.recipe)
  end
end
