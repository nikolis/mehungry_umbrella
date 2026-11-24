defmodule Mehungry.Food.SnackIngredients do
  @moduledoc """
  Admin-curated snack ingredients (`Mehungry.Food.SnackIngredient`) — the
  vetted list the AI meal-plan assistant will be allowed to offer as snacks.

  Two kinds are curated on `/professional/snack-nuts`: `"dried_nut"` and
  `"fresh_fruit"`. The meal planner reads nuts through `selected_ids/1` and fruit
  through `seasonal_fruit_ids/2`, which keeps only the curated fruit that is on the
  market (grown locally or imported) in a country that month (`Mehungry.Food.SeasonalAvailability`).

  Candidates are global (USDA catalog, `user_id IS NULL`) ingredients only.
  """

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.{Category, Ingredient, SeasonalAvailability, SnackIngredient}

  @default_kind "dried_nut"
  @page_size 50

  # The category-name keyword that narrows candidate search for each kind (USDA
  # "Nut and Seed Products", "Fruits and Fruit Juices") — matched with ilike so no
  # category id is hardcoded.
  @category_keyword %{"dried_nut" => "nut", "fresh_fruit" => "fruit"}

  def default_kind, do: @default_kind

  @doc "The snack kinds, in display order."
  def kinds, do: SnackIngredient.kinds()

  @doc "Selected snack rows for `kind`, ingredient + category preloaded, by name."
  def list_selected(kind \\ @default_kind) do
    from(s in SnackIngredient,
      join: i in assoc(s, :ingredient),
      left_join: c in assoc(i, :category),
      where: s.kind == ^kind,
      order_by: [asc: i.name],
      preload: [ingredient: {i, category: c}]
    )
    |> Repo.all()
  end

  @doc "MapSet of the ingredient ids selected for `kind`."
  def selected_ids(kind \\ @default_kind) do
    from(s in SnackIngredient, where: s.kind == ^kind, select: s.ingredient_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Curated `"fresh_fruit"` ingredient ids that are on the market (local or imported) in `country`
  (ISO-2) in `month` (1–12). A curated fruit whose species has no seasonality data is
  left out: its season is unknown.
  """
  def seasonal_fruit_ids(country, month) do
    fruit = selected_ids("fresh_fruit")

    if MapSet.size(fruit) == 0,
      do: fruit,
      else:
        MapSet.intersection(fruit, SeasonalAvailability.available_ingredient_ids(country, month))
  end

  @doc "Marks an ingredient as a snack of `kind`. Idempotent."
  def add(ingredient_id, kind \\ @default_kind, added_by_id \\ nil) do
    %SnackIngredient{}
    |> SnackIngredient.changeset(%{
      ingredient_id: ingredient_id,
      kind: kind,
      added_by_id: added_by_id
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:ingredient_id, :kind])
  end

  @doc "Removes an ingredient from the `kind` snack list. Returns the count removed."
  def remove(ingredient_id, kind \\ @default_kind) do
    {count, _} =
      from(s in SnackIngredient, where: s.ingredient_id == ^ingredient_id and s.kind == ^kind)
      |> Repo.delete_all()

    count
  end

  @doc """
  Global ingredients matching `term` (all words, any order, on `search_name`),
  as `%{id, name, category, food_class}` maps ordered shortest-name first.

  Options:
    * `:kind` (default `"dried_nut"`) — which kind's category keyword applies.
    * `:category_only` (default `true`; `:nuts_only` is the older name) — only
      categories whose name contains the kind's keyword ("nut" for dried nuts,
      "fruit" for fresh fruit).
    * `:limit` (default #{@page_size}), `:offset` (default 0).

  A blank term with `category_only: true` lists the whole category, so the admin
  can browse it without typing.
  """
  def search_candidates(term, opts \\ []) do
    category_only = Keyword.get(opts, :category_only, Keyword.get(opts, :nuts_only, true))
    keyword = Map.fetch!(@category_keyword, Keyword.get(opts, :kind, @default_kind))
    limit = Keyword.get(opts, :limit, @page_size)
    offset = Keyword.get(opts, :offset, 0)
    words = term |> Ingredient.normalize_string() |> String.split(" ", trim: true)

    if words == [] and not category_only do
      []
    else
      from(i in Ingredient,
        left_join: c in Category,
        on: c.id == i.category_id,
        where: is_nil(i.user_id),
        order_by: [asc: fragment("length(?)", i.name), asc: i.name, asc: i.id],
        limit: ^limit,
        offset: ^offset,
        select: %{id: i.id, name: i.name, category: c.name, food_class: i.food_class}
      )
      |> filter_words(words)
      |> filter_category(category_only, keyword)
      |> Repo.all()
    end
  end

  defp filter_words(query, words) do
    Enum.reduce(words, query, fn word, q ->
      where(q, [i], ilike(i.search_name, ^"%#{word}%"))
    end)
  end

  defp filter_category(query, false, _keyword), do: query

  defp filter_category(query, true, keyword),
    do: where(query, [_i, c], ilike(c.name, ^"%#{keyword}%"))
end
