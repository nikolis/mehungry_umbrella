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
      parent_component={assigns.parent_component}
      deleted={assigns.deleted}
    />
    """
  end

  def consume_recipe_user_meal_render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.f, :delete) == true)

    ~H"""
    <.consume_recipe_user_meal
      f={assigns.f}
      recipe_user_meals={assigns.recipe_user_meals}
      recipe_user_meal_ids={assigns.recipe_user_meal_ids}
      parent_component={assigns.parent_component}
      deleted={assigns.deleted}
      user_meal={assigns.user_meal}
    />
    """
  end

  def get_not_nil(first, second) do
    if(first) do
      first
    else
      second
    end
  end

  def is_empty(%Phoenix.HTML.Form{} = form, atom_key) do
    key_form_params = form.params[atom_key]
    key_changeset = form.source.changes[atom_key]
    key_form_data = Map.from_struct(form.data)[atom_key]

    if is_nil(key_form_data) and is_nil(key_changeset) and is_nil(key_form_params) do
      true
    else
      false
    end
  end

  def has_content(form, atom_key) do
    is_e = is_empty(form, atom_key)

    case is_e do
      true ->
        ""

      false ->
        "input_with_content"
    end
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
