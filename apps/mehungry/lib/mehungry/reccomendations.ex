defmodule Mehungry.Reccomendations do
  alias Mehungry.Food.Ingredient
  alias Mehungry.Food

  @alpha 0.00001
  @lambda 0.001
  @attributes [:at_a, :at_b, :at_c]

  def calculate_error_term(theta, attrs, result) do
    prediction = Numexy.dot(theta, attrs)
    abs(prediction - result)
  end

  def calculate_error_term(theta, attrs, result, index) do
    prediction = Numexy.dot(theta, attrs)
    x_i = Numexy.get(attrs, {index, nil})
    reg_term = @lambda * Numexy.get(theta, {index, nil})
    @alpha * ((prediction - result) * x_i + reg_term)
  end

  def calculate_error_term(theta, attrs, result, 0) do
    prediction = Numexy.dot(theta, attrs)
    x_i = Numexy.get(attrs, {0, nil})
    @alpha * ((prediction - result) * x_i)
  end

  def calculate_sum_error_term(thetas, xs, ys) do
    xs_index = Enum.with_index(xs)

    Enum.reduce(xs_index, 0, fn {x, index}, acc ->
      acc + calculate_error_term(thetas, x, Enum.at(ys, index))
    end)
  end

  def calculate_sum_error_term(thetas, xs, ys, ind) do
    xs_index = Enum.with_index(xs)

    Enum.reduce(xs_index, 0, fn {x, index}, acc ->
      acc + calculate_error_term(thetas, x, Enum.at(ys, index), ind)
    end)
  end

  def optimize_thetas(thetas, xs, ys, total_error) do
    thetas_index = Enum.with_index(thetas)
    thetas_num = Numexy.new(thetas)
    total_error_init = calculate_sum_error_term(thetas_num, xs, ys)

    thetas_up =
      Enum.map(thetas_index, fn {theta, index} ->
        update_term = calculate_sum_error_term(thetas_num, xs, ys, index)

        result = theta - update_term
        result
      end)

    thetas_num_up = Numexy.new(thetas_up)
    total_error = calculate_sum_error_term(thetas_num_up, xs, ys)

    if total_error_init <= total_error do
      {thetas, total_error_init}
    else
      optimize_thetas(thetas_up, xs, ys, total_error)
    end
  end

  def get_grade(thetas, x) do
    thetas = Numexy.new(thetas)
    xs = Numexy.new(x)
    Numexy.dot(thetas, xs)
  end

  def get_feature_vector(recipe_list, categories) do
    the_list =
      Enum.map(recipe_list, fn x ->
        list_of_grades =
          Enum.map(x.recipe_ingredients, fn y ->
            ing = Food.get_ingredient(y.ingredient_id)
            category = Food.get_category!(ing.category_id)
            {category.name, y.quantity}
          end)

        map_of_grades = Enum.into(list_of_grades, %{})

        vector =
          Enum.reduce(categories, [], fn x, acc ->
            grade =
              case Map.get(map_of_grades, x) do
                nil ->
                  0

                result ->
                  result
              end

            acc ++ [grade]
          end)

        vector
      end)
  end

  def create_reccomender_model(recipe_list, grades) do
    category_lists =
      Enum.reduce(recipe_list, [], fn x, acc ->
        partial_list =
          Enum.reduce(x.recipe_ingredients, [], fn y, acc ->
            ingredient = Food.get_ingredient(y.ingredient_id)
            category = Food.get_category!(ingredient.category_id)
            acc ++ [category.name]
          end)

        acc ++ partial_list
      end)

    categories = Enum.uniq(category_lists)

    the_list =
      Enum.map(recipe_list, fn x ->
        list_of_grades =
          Enum.map(x.recipe_ingredients, fn y ->
            ing = Food.get_ingredient(y.ingredient_id)
            category = Food.get_category!(ing.category_id)
            {category.name, y.quantity}
          end)

        map_of_grades = Enum.into(list_of_grades, %{})

        vector =
          Enum.reduce(categories, [], fn x, acc ->
            grade =
              case Map.get(map_of_grades, x) do
                nil ->
                  0

                result ->
                  result
              end

            acc ++ [grade]
          end)

        vector
      end)
  end
end
