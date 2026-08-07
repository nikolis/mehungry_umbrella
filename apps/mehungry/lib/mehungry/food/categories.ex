defmodule Mehungry.Food.Categories do
  @moduledoc """
  Ingredient categories and food restriction types.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Category, FoodRestrictionType}

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs \\ %{}) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  def get_category!(id) do
    Repo.get(Category, id)
  end

  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  def get_category_by_name(nil) do
    nil
  end

  def get_category_by_name(name) do
    from(cate in Category,
      where: cate.name == ^name
    )
    |> Repo.one()
  end

  def list_categories() do
    Repo.all(Category)
  end

  def search_category(term) do
    term = "%" <> term <> "%"

    query =
      from mu in Category,
        where: ilike(mu.name, ^term)

    Repo.all(query)
  end

  def list_food_restriction_types() do
    Repo.all(from(a in FoodRestrictionType))
  end

  # Animal-product categories excluded by each base diet, plus flag add-ons.
  @diet_category_names %{
    vegan: ~w(fish Poultry Dairy Pork Sausages Lamb Beef),
    vegetarian: ~w(fish Poultry Pork Sausages Lamb Beef),
    pescatarian: ~w(Poultry Pork Sausages Lamb Beef),
    omnivore: []
  }

  @doc """
  Resolves a base diet (`:omnivore | :vegetarian | :vegan | :pescatarian`) plus
  combinable flags (currently `:lactose_intolerant`) into the **union** of the
  ingredient-category ids a user of that diet avoids. Additive and deduped, so
  e.g. `diet_category_ids(:vegetarian, [:lactose_intolerant])` includes Dairy.
  """
  def diet_category_ids(base_diet, flags \\ []) do
    base = Map.get(@diet_category_names, base_diet, [])
    flag_names = if :lactose_intolerant in flags, do: ["Dairy"], else: []

    (base ++ flag_names)
    |> Enum.uniq()
    |> Enum.map(fn name -> name |> search_category() |> List.first() end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
  end
end
