defmodule MehungryWeb.SelectComponentUtils do
  def get_selected_items_database(form_params, input_variable, assigns, get_by_id_func) do
    label_function =
      case Map.get(assigns, :label_function) do
        nil ->
          fn x -> x.name end

        label_f ->
          label_f
      end

    case Map.get(form_params, input_variable) do
      nil ->
        case Map.get(assigns.form.data, :ingredient_id) do
          nil ->
            nil

          _ ->
            item = Map.get(assigns.form.data, :ingredient)
            %{label: label_function.(item), id: item.id}
        end

      str_id ->
        result = Integer.parse(str_id)

        case result do
          :error ->
            nil

          {num_id, _} ->
            item = get_by_id_func.(num_id)
            %{name: label_function.(item), id: item.id}
        end
    end
  end

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

  def get_selected_items(nil, %{}, input_variable, label_function, assigns) do
    []
  end

  def get_selected_items(nil, nil, input_variable, label_function, assigns) do
    []
  end

  def get_selected_items(changes, form_params, input_variable, label_function, assigns) do
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
      {nil, nil, nil, nil} ->
        []

      {nil, nil, nil, form_date} ->
        form_date

      {nil, nil, selected_items, _} ->
        selected_items

      {nil, form_params, _, _} ->
        []

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
