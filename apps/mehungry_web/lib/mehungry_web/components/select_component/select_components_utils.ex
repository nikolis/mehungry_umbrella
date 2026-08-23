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
    input_variable_form_params = []

    input_variable_changeset =
      if length(Map.keys(changes)) > 0 do
        Map.get(changes, input_variable)
      else
        nil
      end

    selected_items = Map.get(assigns, :selected_items)

    input_variable_form_data = Map.get(assigns.form.data, input_variable)

    tuple_results =
      {input_variable_changeset, input_variable_form_params, selected_items,
       input_variable_form_data}

    case tuple_results do
      {nil, _form_params, nil, nil} ->
        []

      {nil, _form_params, nil, form_date} ->
        form_date

      {nil, _form_params, selected_items, _} ->
        selected_items

      # get_items_from_params(form_params, assigns.items)
      {selected_items, _, _, _} ->
        selected_items =
          if is_map(selected_items) do
            {selected_items.id, selected_items.name}
          else
            selected_items
          end

        Enum.filter(assigns.items, fn x ->
          if is_binary(selected_items) do
            String.contains?(selected_items, elem(x, 0))
          else
            selected_items == String.to_integer(elem(x, 0))
          end
        end)
    end
  end
end
