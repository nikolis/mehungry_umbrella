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

  Each keyword expands to **every** matching category, not just the first — a
  single keyword like "Lamb" matches several seeded meat categories ("Lamb,
  Veal, and Game Products", "Lamb, goat, game"), and all of them must be
  excluded.
  """
  def diet_category_ids(base_diet, flags \\ []) do
    base_diet
    |> diet_category_id_groups(flags)
    |> List.flatten()
    |> Enum.uniq()
  end

  # The excluded categories for a diet, grouped by the keyword that matched them.
  # A keyword's group holds *every* category whose name contains it (ilike
  # substring), because one keyword can name several seeded categories that are
  # all off-limits. Grouping (rather than a flat set) lets `diet_mode` detection
  # treat "excludes any category in the group" as satisfying that keyword, so a
  # user whose saved rules predate a newly-seeded matching category still counts.
  defp diet_category_id_groups(base_diet, flags) do
    base = Map.get(@diet_category_names, base_diet, [])
    flag_names = if :lactose_intolerant in flags, do: ["Dairy"], else: []

    (base ++ flag_names)
    |> Enum.uniq()
    |> Enum.map(fn name -> name |> search_category() |> Enum.map(& &1.id) end)
    |> Enum.reject(&(&1 == []))
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

    cond do
      covers_diet?(:vegan, excluded) -> :vegan
      covers_diet?(:vegetarian, excluded) -> :vegetarian
      true -> nil
    end
  end

  # A rule set covers a diet when it excludes at least one category from *every*
  # keyword group of that diet (see `diet_category_id_groups/2`). Using per-group
  # intersection rather than a subset over the flat union means a user counts as
  # e.g. vegan even if their saved rules only carry one of several categories a
  # keyword now matches. Empty vocabulary (unseeded categories) → no group → false,
  # so a diet is never inferred from nothing.
  defp covers_diet?(base_diet, excluded) do
    groups = diet_category_id_groups(base_diet, [])

    groups != [] and
      Enum.all?(groups, fn ids -> not MapSet.disjoint?(MapSet.new(ids), excluded) end)
  end
end
