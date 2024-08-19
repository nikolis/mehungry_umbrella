defmodule MehungryWeb.SelectComponentUtils do
  def get_selected_items_database(form_params, input_variable, assigns, get_by_id_func) do
    label_function =
      case Map.get(assigns, :label_function) do
        nil ->
          fn x -> x.name end

        label_f ->
          label_f
      end

    atom_input_variable = String.to_existing_atom(assigns.input_variable)

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
            %{label: label_function.(item), id: item.id}
        end
    end
  end

  def get_selected_items(form_params, input_variable, assigns) do
    label_function =
      case Map.get(assigns, :label_function) do
        nil ->
          fn x -> x.name end

        label_f ->
          label_f
      end

    atom_input_variable = String.to_existing_atom(assigns.input_variable)

    case Map.get(form_params, input_variable) do
      nil ->
        if is_nil(Map.get(assigns, :selected_items)) do
          case Map.get(assigns.form.data, atom_input_variable) do
            nil ->
              nil

            id ->
              if is_nil(Map.get(assigns, :items)) do
                nil
              else
                item = Enum.find(assigns.items, nil, fn x -> x.id == id end)

                if(item) do
                  %{id: item.id, label: label_function.(item)}
                end
              end
          end
        else
          assigns.selected_items
        end

      str_id ->
        result = Integer.parse(str_id)

        case result do
          :error ->
            nil

          {num_id, _} ->
            selected_item = Enum.find(assigns.items, fn x -> x.id == num_id end)

            if is_nil(selected_item) do
              nil
            else
              %{id: selected_item.id, label: label_function.(selected_item)}
            end
        end
    end
  end
end
