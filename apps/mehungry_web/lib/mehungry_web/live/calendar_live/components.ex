defmodule MehungryWeb.CalendarLive.Components do
  use Phoenix.Component
  use MehungryWeb, :live_component

  embed_templates("components/*")

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

  def select_recipe_modal(assigns) do
    ~H"""
      <.modal_select_meal   live_action={assigns.live_action}  changeset={assigns.changeset} recipes = {assigns.recipes} />
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
