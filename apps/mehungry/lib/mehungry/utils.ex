defmodule Mehungry.Utils do
  @measurement_units [["ml", "l"], ["gram", "kg"], ["grammar", "kg"]]

  @doc """
   A function that a Map , Key as string and value
   puts the key,value pair with a key according to the existing keys of the Map
  i.e 
  map , %{the_atom: "lor"} 
  put_map(map, "new_key", "value")
  is going to return %{the_atom: "lor", new_key: "value"}
  """
  def put_map(map, key, value) when map == %{} do
    Map.put(map, key, value)
  end

  def put_map(the_map, key, value) do
    first_key = Enum.at(Map.keys(the_map), 0)

    if(is_atom(first_key) and !is_atom(key)) do
      Map.put(the_map, String.to_atom(key), value)
    else
      if is_binary(first_key) and is_atom(key) do
        Map.put(the_map, to_string(key), value)
      else
        Map.put(the_map, key, value)
      end
    end
  end

  def remove_parenthesis(text) do
    text
    |> String.replace(~r"\(.*\)", "")
    |> String.replace(~r", ,", ",")
    |> String.replace(~r",,", ",")
  end

  def sort_ingredients_for_basket(ingredients) do
    Enum.sort_by(ingredients, fn x -> x.in_storage end, fn a, b -> a > b end)
  end

  def normilize_ingredient(ingredient_params) do
    measurement_unit_id = ingredient_params["measurement_unit_id"]
    quantity = ingredient_params["quantity"]
    measurement_unit = Mehungry.Food.get_measurement_unit!(measurement_unit_id)
    result = normilize_measurement_unit(measurement_unit.name, quantity)
    {quantity_new, mu_name} = result
    [measurement_unit_new] = Mehungry.Food.get_measurement_unit_by_name(mu_name)

    Enum.into(
      %{"measurement_unit_id" => measurement_unit_new.id, "quantity" => quantity_new},
      ingredient_params
    )
  end

  def normilize_measurement_unit(m_u, value) do
    m_u = to_string(m_u)

    if(value < 1) do
      {value * 1000, get_smaller_mu(m_u)}
    else
      result = trunc(value) / 1000

      if(result > 0) do
        {result, get_bigger_mu(m_u)}
      else
        {value, m_u}
      end
    end
  end

  def get_bigger_mu(measurement_unit, m_index \\ 0) do
    list = Enum.at(@measurement_units, m_index)

    case list do
      nil ->
        measurement_unit

      mu_list ->
        index = Enum.find_index(mu_list, fn x -> x == measurement_unit end)

        case index do
          nil ->
            get_bigger_mu(measurement_unit, m_index + 1)

          number ->
            if(number >= length(mu_list) - 1) do
              measurement_unit
            else
              Enum.at(mu_list, number + 1)
            end
        end
    end
  end

  def get_smaller_mu(measurement_unit, m_index \\ 0) do
    list = Enum.at(@measurement_units, m_index)

    case list do
      nil ->
        measurement_unit

      mu_list ->
        index = Enum.find_index(mu_list, fn x -> x == measurement_unit end)

        case index do
          nil ->
            get_smaller_mu(measurement_unit, m_index + 1)

          number ->
            if(number - 1 < 0 or number > length(mu_list)) do
              measurement_unit
            else
              Enum.at(mu_list, number - 1)
            end
        end
    end
  end
end
