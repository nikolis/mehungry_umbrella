defmodule Mehungry.Inventory do
  @moduledoc """
  The Inventory context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo
  alias Mehungry.Inventory.BasketItem
  alias Mehungry.Inventory.BasketParams

  def change_basket_params(%BasketParams{} = basket_params, attrs \\ %{}) do
    BasketParams.changeset(basket_params, attrs)
  end

  alias Mehungry.Inventory.ShoppingBasket

  @doc """
  Returns the list of shopping_baskets.

  ## Examples

      iex> list_shopping_baskets()
      [%ShoppingBasket{}, ...]

  """
  def list_shopping_baskets do
    Repo.all(ShoppingBasket)
  end

  def list_shopping_baskets_for_user(user_id) do
    from(s in ShoppingBasket,
      where: s.user_id == ^user_id
    )
    |> Repo.all()
    |> Repo.preload(
      basket_items: [
        :measurement_unit
      ],
      basket_ingredients: [
        :measurement_unit,
        ingredient: [
          :category,
          :ingredient_translation
        ]
      ]
    )
  end

  @doc """
  Gets a single shopping_basket.

  Raises `Ecto.NoResultsError` if the Shoping basket does not exist.

  ## Examples

      iex> get_shopping_basket!(123)
      %ShoppingBasket{}

      iex> get_shopping_basket!(456)
      ** (Ecto.NoResultsError)

  """
  def get_shopping_basket!(id) do
    Repo.get!(ShoppingBasket, id)
    |> Repo.preload(
      basket_items: [
        :measurement_unit
      ],
      basket_ingredients: [
        :measurement_unit,
        ingredient: [
          :category,
          :ingredient_translation
        ]
      ]
    )
  end

  @doc """
  Creates a shopping_basket.

  ## Examples

      iex> create_shopping_basket(%{field: value})
      {:ok, %ShoppingBasket{}}

      iex> create_shopping_basket(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs) do
    result =
      shopping_basket
      |> ShoppingBasket.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, basket} ->
        basket =
          basket
          |> Repo.preload(
            basket_ingredients: [
              :measurement_unit,
              ingredient: [
                :category,
                :ingredient_translation
              ]
            ]
          )

        {:ok, basket}

      _ ->
        result
    end
  end

  def add_item(basket_id, item_params) do
    if !is_nil(basket_id) do
      basket = get_shopping_basket!(basket_id)

      result =
        %BasketItem{}
        |> BasketItem.changeset(%{
          list_id: basket.id,
          name: item_params.name,
          quantity: item_params.quantity,
          shopping_basket_id: basket_id,
          measurement_unit_id: item_params.measurement_unit_id,
          nutrition_data: item_params.nutrition,
          usda_fdc_id: item_params.usda_fdc_id,
          checked: false
        })
        |> Repo.insert()

      case result do
        {:ok, result} ->
          {:ok, Repo.preload(result, :measurement_unit)}

        {:eror, problem} ->
          {:error, problem}
      end
    else
      {:error, :nil_basket_id}
    end
  end

  @doc """
  Adds all of a recipe's ingredients to a basket as `basket_items`, scaling
  quantities by `servings_scale`. Reads the recipe's `recipe_ingredients`
  (the current schema). Returns `{:ok, count}`.
  """
  def add_items_from_recipe(basket_id, recipe, servings_scale \\ 1) do
    basket = get_shopping_basket!(basket_id)
    recipe = Repo.preload(recipe, recipe_ingredients: [:ingredient, :measurement_unit])
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    items =
      Enum.map(recipe.recipe_ingredients, fn ri ->
        %{
          name: item_name(ri),
          quantity: (ri.quantity || 1) * servings_scale,
          measurement_unit_id: ri.measurement_unit_id,
          shopping_basket_id: basket.id,
          recipe_id: recipe.id,
          in_storage: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(BasketItem, items)
    {:ok, count}
  end

  defp item_name(recipe_ingredient) do
    recipe_ingredient.ingredient_allias ||
      (recipe_ingredient.ingredient && recipe_ingredient.ingredient.name) || "ingredient"
  end

  @doc """
  Returns the user's active basket (most recent), creating an empty "Groceries"
  basket when the user has none. There is no per-row "active" flag — the mobile
  API treats the latest basket as active.
  """
  def get_or_create_basket_for_user(user_id) do
    basket =
      from(s in ShoppingBasket, where: s.user_id == ^user_id, order_by: [desc: s.id], limit: 1)
      |> Repo.one()

    case basket do
      %ShoppingBasket{} = b ->
        get_shopping_basket!(b.id)

      nil ->
        {:ok, created} = create_shopping_basket(%{"user_id" => user_id, "title" => "Groceries"})
        get_shopping_basket!(created.id)
    end
  end

  @doc "Gets a basket item (with its measurement unit)."
  def get_basket_item!(id), do: Repo.get!(BasketItem, id) |> Repo.preload(:measurement_unit)

  @doc "Updates a basket item (quantity / in_storage / name …)."
  def update_basket_item(%BasketItem{} = item, attrs) do
    item
    |> BasketItem.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, item} -> {:ok, Repo.preload(item, :measurement_unit)}
      other -> other
    end
  end

  @doc "Deletes a basket item."
  def delete_basket_item(%BasketItem{} = item), do: Repo.delete(item)

  @doc """
  Adds a planned meal's items to a basket: every recipe in the meal contributes
  its ingredients (scaled by consume portions), plus the meal's direct
  ingredients. Returns `{:ok, count}`.
  """
  def add_items_from_meal(basket_id, %Mehungry.History.UserMeal{} = meal) do
    meal =
      Mehungry.Repo.preload(meal,
        recipe_user_meals: [recipe: [recipe_ingredients: [:ingredient, :measurement_unit]]],
        ingredient_user_meals: [:ingredient, :measurement_unit]
      )

    recipe_added =
      meal.recipe_user_meals
      |> Enum.map(fn rum ->
        {:ok, n} = add_items_from_recipe(basket_id, rum.recipe, rum.consume_portions || 1)
        n
      end)
      |> Enum.sum()

    basket = get_shopping_basket!(basket_id)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    ingredient_items =
      Enum.map(meal.ingredient_user_meals, fn ium ->
        %{
          name: (ium.ingredient && ium.ingredient.name) || "ingredient",
          quantity: ium.quantity || 1,
          measurement_unit_id: ium.measurement_unit_id,
          shopping_basket_id: basket.id,
          in_storage: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    {ing_count, _} = Repo.insert_all(BasketItem, ingredient_items)
    {:ok, recipe_added + ing_count}
  end

  def create_shopping_basket(attrs \\ %{}) do
    result =
      %ShoppingBasket{}
      |> ShoppingBasket.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, basket} ->
        basket =
          basket
          |> Repo.preload(
            basket_ingredients: [
              :measurement_unit,
              ingredient: [
                :category,
                :ingredient_translation
              ]
            ]
          )

        {:ok, basket}

      _ ->
        result
    end
  end

  @doc """
  Creates a new shopping basket for `user_id` populated with the aggregated
  ingredients of every meal logged in the inclusive `start_date..end_date` span
  (e.g. the week currently shown on the calendar). Returns `{:ok, basket}` /
  `{:error, changeset}`; the basket is created even when the span has no meals
  (an empty list to start from).
  """
  def create_basket_for_range(user_id, %Date{} = start_date, %Date{} = end_date, title) do
    start_dt = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_dt = NaiveDateTime.new!(end_date, ~T[00:00:00])

    basket_ingredients =
      Mehungry.History.list_history_user_meals_for_user(user_id, start_dt, end_dt)
      |> aggregate_meal_ingredients()

    create_shopping_basket(%{
      "user_id" => user_id,
      "title" => title,
      "start_dt" => start_dt,
      "end_dt" => end_dt,
      "basket_ingredients" => basket_ingredients
    })
  end

  @doc """
  Returns the user's existing shopping basket for the week starting on
  `start_date` (matched on the `start_dt` that `create_basket_for_range/4`
  stamps — Monday 00:00), or `nil`. Lets callers open an already-built week
  list instead of creating a duplicate.
  """
  def get_basket_for_week(user_id, %Date{} = start_date) do
    start_dt = NaiveDateTime.new!(start_date, ~T[00:00:00])

    from(s in ShoppingBasket,
      where: s.user_id == ^user_id and s.start_dt == ^start_dt,
      order_by: [desc: s.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Aggregates a list of `History.UserMeal`s into `basket_ingredients` attrs:
  every recipe ingredient scaled by its meal's logged portions, summed per
  `(ingredient_id, measurement_unit_id)`. Returns a list of string-keyed maps
  (`"ingredient_id"`, `"quantity"`, `"measurement_unit_id"`, `"description"`)
  ready to cast into a `ShoppingBasket`. The meals must be preloaded with
  `recipe_user_meals: [recipe: [recipe_ingredients: [:ingredient_portion, ...]]]`.

  Shared by the basket-builder LiveViews and `create_basket_for_range/4` so the
  scaling/dedup rules live in one place.
  """
  def aggregate_meal_ingredients(user_meals) do
    user_meals
    |> Enum.flat_map(fn meal -> meal.recipe_user_meals end)
    |> Enum.flat_map(fn rum ->
      servings = rum.recipe.servings
      portions = rum.cooking_portions

      Enum.map(rum.recipe.recipe_ingredients, fn ri ->
        {ri.ingredient_id, scaled_quantity(ri.quantity, servings, portions),
         ri.measurement_unit_id, portion_description(ri)}
      end)
    end)
    |> Enum.reduce(%{}, fn {ing, quant_out, mu, desc}, acc ->
      with {ing, quant, mu_e, desc_e} <- Map.get(acc, Integer.to_string(ing)),
           true <- mu == mu_e do
        Map.replace(acc, Integer.to_string(ing), {ing, quant + quant_out, mu_e, desc_e})
      else
        _ -> Map.put_new(acc, Integer.to_string(ing), {ing, quant_out, mu, desc})
      end
    end)
    |> Map.values()
    |> Enum.map(fn {ing, quant, mu, desc} ->
      %{
        "ingredient_id" => ing,
        "quantity" => quant,
        "measurement_unit_id" => mu,
        "description" => desc
      }
    end)
  end

  # Free-text label for a recipe ingredient that uses a description-only portion
  # (no measurement unit), so the basket can still show e.g. "1 medium banana".
  defp portion_description(%{measurement_unit_id: nil, ingredient_portion: %{description: d}}),
    do: d

  defp portion_description(_), do: nil

  # Scales a recipe ingredient's per-recipe quantity to the logged portion:
  # (quantity / servings) * cooking_portions. Any of the three can be missing on
  # older/partial recipe data (nil servings, nil cooking_portions, nil quantity)
  # or servings can be 0 — either of which would raise an ArithmeticError — so
  # default to safe values (servings/portions → 1, qty → 0).
  defp scaled_quantity(quantity, servings, portions) do
    qty = as_number(quantity, 0)
    svgs = as_number(servings, 1)
    svgs = if svgs == 0, do: 1, else: svgs
    prt = as_number(portions, 1)

    Float.round(qty / svgs * prt, 2)
  end

  defp as_number(n, _default) when is_number(n), do: n
  defp as_number(_, default), do: default

  @doc """
  Deletes a shopping_basket.

  ## Examples

      iex> delete_shopping_basket(shopping_basket)
      {:ok, %ShoppingBasket{}}

      iex> delete_shopping_basket(shopping_basket)
      {:error, %Ecto.Changeset{}}

  """
  def delete_shopping_basket(%ShoppingBasket{} = shopping_basket) do
    Repo.delete(shopping_basket)
  end

  def delete_all_baskets_for_user(user_id) do
    from(basket in ShoppingBasket,
      where: basket.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking shopping_basket changes.

  ## Examples

      iex> change_shopping_basket(shopping_basket)
      %Ecto.Changeset{data: %ShoppingBasket{}}

  """
  def change_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs \\ %{}) do
    ShoppingBasket.changeset(shopping_basket, attrs)
  end

  alias Mehungry.Inventory.BasketIngredient

  @doc """
  Returns the list of basket_ingredients.

  ## Examples

      iex> list_basket_ingredients()
      [%BasketIngredient{}, ...]

  """
  def list_basket_ingredients do
    Repo.all(BasketIngredient)
  end

  @doc """
  Gets a single basket_ingredient.

  Raises `Ecto.NoResultsError` if the Ingredient basket does not exist.

  ## Examples

      iex> get_shopping_basket_ingredient!(123)
      %BasketIngredient{}

      iex> get_shopping_basket_ingredient!(456)
      ** (Ecto.NoResultsError)

  """
  def get_shopping_basket_ingredient!(id), do: Repo.get!(BasketIngredient, id)

  @doc """
  Creates a basket_ingredient.

  ## Examples

      iex> create_basket_ingredient(%{field: value})
      {:ok, %BasketIngredient{}}

      iex> create_basket_ingredient(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_basket_ingredient(attrs \\ %{}) do
    %BasketIngredient{}
    |> BasketIngredient.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a basket_ingredient.

  ## Examples

      iex> update_basket_ingredient(basket_ingredient, %{field: new_value})
      {:ok, %BasketIngredient{}}

      iex> update_basket_ingredient(basket_ingredient, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs) do
    basket_ingredient
    |> BasketIngredient.changeset(attrs)
    |> Repo.update()
  end

  def toggle_basket_ingredient(%BasketItem{} = basket_item) do
    basket_item
    |> BasketItem.changeset(%{in_storage: not basket_item.in_storage})
    |> Repo.update()
  end

  def toggle_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
    basket_ingredient
    |> BasketIngredient.changeset(%{in_storage: not basket_ingredient.in_storage})
    |> Repo.update()
  end

  @doc """
  Deletes a basket_ingredient.

  ## Examples

      iex> delete_basket_ingredient(basket_ingredient)
      {:ok, %BasketIngredient{}}

      iex> delete_basket_ingredient(basket_ingredient)
      {:error, %Ecto.Changeset{}}

  """
  def delete_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
    Repo.delete(basket_ingredient)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking basket_ingredient changes.

  ## Examples

      iex> change_basket_ingredient(basket_ingredient)
      %Ecto.Changeset{data: %BasketIngredient{}}

  """
  def change_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs \\ %{}) do
    BasketIngredient.changeset(basket_ingredient, attrs)
  end
end
