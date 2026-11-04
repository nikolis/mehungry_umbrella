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
      unit_options={@unit_options}
      current_user_id={assigns.current_user_id}
      current_language={Map.get(assigns, :current_language, "en")}
      parent_component={assigns.parent_component}
      deleted={assigns.deleted}
    />
    """
  end

  # Compact one-line summary shown under a recipe's title in the meal-plan recipe
  # picker (cooking time · servings · cuisine). Each part is dropped when absent.
  def recipe_subtitle(recipe) do
    [recipe_time(recipe), recipe_servings(recipe), recipe_cuisine(recipe)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp recipe_time(%{cooking_time_lower_limit: lo, cooking_time_upper_limit: hi}) do
    case {lo, hi} do
      {nil, nil} -> nil
      {lo, nil} -> "#{lo} min"
      {nil, hi} -> "#{hi} min"
      {lo, hi} when lo == hi -> "#{lo} min"
      {lo, hi} -> "#{lo}–#{hi} min"
    end
  end

  defp recipe_time(_), do: nil

  defp recipe_servings(%{servings: n}) when is_integer(n) and n > 0, do: "#{n} servings"
  defp recipe_servings(_), do: nil

  defp recipe_cuisine(%{cousine: c}) when is_binary(c) and c != "", do: c
  defp recipe_cuisine(_), do: nil

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
