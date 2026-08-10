defmodule MehungryWeb.CalendarLive.Components do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  embed_templates("components/*")

  def recipe_user_meal_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.f, :delete) == true)

    ~H"""
    <.recipe_user_meal
      f={assigns.f}
      recipe_ids={assigns.recipe_ids}
      recipes={assigns.recipes}
      mode={@mode}
      myself={@myself}
      parent_component={assigns.parent_component}
      deleted={assigns.deleted}
    />
    """
  end

  def ingredient_user_meal_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.f, :delete) == true)

    ~H"""
    <.ingredient_user_meal
      f={assigns.f}
      recipe_ids={assigns.recipe_ids}
      recipes={assigns.recipes}
      mode={@mode}
      myself={@myself}
      measurement_units={@measurement_units}
      current_user_id={assigns.current_user_id}
      condition_ids={assigns.condition_ids}
      parent_component={assigns.parent_component}
      deleted={assigns.deleted}
    />
    """
  end

  def is_open(action, invocations) do
    case action do
      :new ->
        "is-open"

      _ ->
        if invocations > 1 do
          "is-closing"
        else
          "is-closed"
        end
    end
  end
end
