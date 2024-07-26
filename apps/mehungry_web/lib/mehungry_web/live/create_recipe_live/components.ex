defmodule MehungryWeb.CreateRecipeLive.Components do
  use Phoenix.Component

  use PhoenixHTMLHelpers
  import MehungryWeb.CoreComponents
  import Ecto.Query 
  alias Mehungry.Repo
  alias Mehungry.Food

  embed_templates("components/*")

  def ingredient_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.g, :delete) == true)
    ing_val =  Phoenix.HTML.Form.input_value(assigns.g, :ingredient_id)
    measurement_units = 
      case is_nil(ing_val)   do
        true ->
          assigns.measurement_units 
        false -> 
          if(!is_binary(ing_val)) do
            portions = (from ingp in Mehungry.Food.IngredientPortion, where: ingp.ingredient_id == ^ing_val) |> Repo.all() 
            IO.inspect(portions)
      
            measurement_units =  Enum.map(portions, 
              fn x -> 
                     Food.get_measurement_unit!(x.measurement_unit_id)
                   end)
              |> Enum.filter(fn x -> !is_nil(x) end)
  
            IO.inspect(ing_val, label: "Choseeen thiss--------------------------------------------------------------------------------------------------------------------------------------------")
            IO.inspect(measurement_units)
            measurement_units = assigns.measurement_units ++ measurement_units
          else
            assigns.measurement_units
          end
      end
     assigns = assign(assigns, :measurement_units, measurement_units)

    ~H"""
    <.ingredient g={assigns.g} ingredients={assigns.ingredients} measurement_units={assigns.measurement_units} style={get_style(assigns.deleted)}  deleted={assigns.deleted}/>
    """
  end

  def get_style(deleted) do
    if(deleted) do
      "display: none;"
    else
      "display: block;"
    end
  end

  def step_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.v, :delete) == true)

    ~H"""
    <.step v={assigns.v} deleted={assigns.deleted}/>
    """
  end

  def recipe_render(assigns) do
    ~H"""
    <.recipe f={assigns.f}/>
    """
  end
end
