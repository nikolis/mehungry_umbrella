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

  @doc """
  The reverse of `diet_category_ids/2`: infers a user's diet "mode"
  (`:vegan | :vegetarian | nil`) from the set of category ids they exclude
  (their persisted `UserCategoryRule`s). Returns `:vegan` when the excluded set
  covers every vegan-excluded category, else `:vegetarian` when it covers the
  vegetarian set. Guards against an empty excluded vocabulary (unseeded
  categories) so it never misclassifies everyone as vegan.

  Accepts the rules (any structs/maps exposing `category_id`) or a list of ids.
  """
  def diet_mode_for_category_rules(rules) do
    excluded =
      rules
      |> Enum.map(fn
        %{category_id: id} -> id
        id when is_integer(id) -> id
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    vegan = MapSet.new(diet_category_ids(:vegan))
    vegetarian = MapSet.new(diet_category_ids(:vegetarian))

    cond do
      MapSet.size(vegan) > 0 and MapSet.subset?(vegan, excluded) -> :vegan
      MapSet.size(vegetarian) > 0 and MapSet.subset?(vegetarian, excluded) -> :vegetarian
      true -> nil
    end
  end
end
