defmodule MehungryWeb.CreateRecipeLive.Components do
  use Phoenix.Component
  
  import Phoenix.HTML.Form
  import MehungryWeb.ErrorHelpers

  embed_templates("forms/*")

  def ingredient_render(assigns) do
    ~H"""
    <.ingredient g={assigns.g} ingredients={assigns.ingredients} measurement_units={assigns.measurement_units}/>
    """
  end

  def step_render(assigns) do
    ~H"""
    <.step v={assigns.v}/>
    """
  end

  def recipe_render(assigns) do
    ~H"""
    <.recipe f={assigns.f}/>
    """
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
end
