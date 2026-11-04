defmodule MehungryWeb.SelectComponentUtils do
  def transform_item(nil) do
    nil
  end

  def transform_item(item, label_function) do
    {item.id, label_function.(item)}
  end

  def get_items_from_params(form_params, items) do
    form_params = String.split(form_params, ",")
    Enum.filter(items, fn x -> elem(x, 0) in form_params end)
  end

  def get_selected_items(nil, %{}, _input_variable, _label_function, _assigns) do
    []
  end

  def get_selected_items(nil, nil, _input_variable, _label_function, _assigns) do
    []
  end

  def get_selected_items(changes, _form_params, input_variable, _label_function, assigns) do
    selected_items = Map.get(assigns, :selected_items)
    input_variable_form_data = Map.get(assigns.form.data, input_variable)

    if input_variable in [:unit_selection, "unit_selection"] do
      File.write!(
        "/tmp/claude-1000/-home-nikolis-git-mehungry-umbrella/605a6c0a-06b3-4d18-9047-b20c463fb7f6/scratchpad/sc_debug.log",
        "IV=#{inspect(input_variable)} changes=#{inspect(changes)} has_key=#{is_map(changes) and Map.has_key?(changes, input_variable)} items=#{inspect(assigns.items)} form_data=#{inspect(input_variable_form_data)}\n",
        [:append]
      )
    end

    # A field is "touched" the moment the changeset carries an entry for it —
    # which happens as soon as the user picks *or clears* a value (the JS hook
    # writes the id, or an empty string, into the hidden input and the form
    # re-validates). We must distinguish "key present but nil" (the user cleared
    # the select) from "key absent" (an untouched, freshly rendered field): only
    # the latter may fall back to the persisted `form.data`. Resurrecting the
    # persisted value on a deliberate clear is what made the widget snap back to
    # the old selection instead of letting the user search for a replacement.
    cond do
      is_map(changes) and Map.has_key?(changes, input_variable) ->
        case Map.get(changes, input_variable) do
          nil ->
            []

          change_value ->
            change_value =
              if is_map(change_value) do
                {change_value.id, change_value.name}
              else
                change_value
              end

            Enum.filter(assigns.items, fn x ->
              if is_binary(change_value) do
                String.contains?(change_value, elem(x, 0))
              else
                change_value == String.to_integer(elem(x, 0))
              end
            end)
        end

      not is_nil(selected_items) ->
        selected_items

      not is_nil(input_variable_form_data) ->
        input_variable_form_data

      true ->
        []
    end
  end
end
