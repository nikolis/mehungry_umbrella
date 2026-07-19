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
end
