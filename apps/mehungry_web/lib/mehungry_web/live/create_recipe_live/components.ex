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

    ing_val =
      case is_nil(Phoenix.HTML.Form.input_value(assigns.g, :ingredient_id)) do
        true ->
          if(length(assigns.f.data.recipe_ingredients) > 0) do
            if is_nil(Enum.at(assigns.f.data.recipe_ingredients, assigns.g.index)) do
              nil
            else
              Enum.at(assigns.f.data.recipe_ingredients, assigns.g.index).id
            end
          else
            nil
          end

        false ->
          Phoenix.HTML.Form.input_value(assigns.g, :ingredient_id)
      end

    measurement_units = get_measurement_unit(ing_val, assigns)
    assigns = assign(assigns, :measurement_units, measurement_units)

    ~H"""
    <div class="py-2">
      <.ingredient
        g={assigns.g}
        ingredients={assigns.ingredients}
        measurement_units={assigns.measurement_units}
        style={get_style(assigns.deleted)}
        deleted={assigns.deleted}
      />
    </div>
    """
  end

  def get_measurement_unit(nil, assigns), do: assigns.measurement_units

  def get_measurement_unit(ing_val, assigns) when is_binary(ing_val),
    do: assigns.measurement_units ++ get_measurement_unit(ing_val)

  def get_measurement_unit(ing_val, assigns) when is_integer(ing_val),
    do: assigns.measurement_units ++ get_measurement_unit(ing_val)

  def get_measurment_unit("", assigns), do: assigns.measurement_units

  def get_measurement_unit(ing_val, assigns) do
    ing_val = String.to_integer(ing_val)
    assigns.measurement_units ++ get_measurement_unit(ing_val)
  end

  defp get_measurement_unit(ing_val) do
    Food.get_measurement_unit_portions_for_ingredient(ing_val)
    |> Enum.map(fn x -> x.measurement_unit end)
    |> Enum.filter(fn x -> !is_nil(x) end)
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
    <.step v={assigns.v} deleted={assigns.deleted} />
    """
  end

  def recipe_render(assigns) do
    ~H"""
    <.recipe f={assigns.f} items={@items} />
    """
  end
end
