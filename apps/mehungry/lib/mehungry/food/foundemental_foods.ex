defmodule Mehungry.Food.FoundementalFoods do
  @moduledoc """
  Curation layer mapping USDA-backed ingredients onto a registry of
  fundamental food species (`FoundementalFoodSpecies`) via `FoundementalFood`
  join rows. Backs the admin USDA Schema view: an ingredient assigned to a
  species drops out of the "to classify" lists and reappears grouped under its
  species.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    FoundementalFood,
    FoundementalFoodSpecies,
    FoundementalFoodSpeciesTranslation,
    Ingredient,
    SpeciesCompoundRelationship,
    SpeciesIcons
  }

  # ── Species ────────────────────────────────────────────────────────────────

  @doc "All species ordered by name (then variety). Admin scope — includes private."
  def list_species do
    Repo.all(from s in FoundementalFoodSpecies, order_by: [asc: s.name, asc: s.variety])
  end

  @doc """
  Public scope — only species not marked `private`. The mobile API's species list
  reads this (the admin USDA Schema view reads `list_species/0`, which includes
  private rows so they stay curatable).
  """
  def list_public_species do
    Repo.all(
      from s in FoundementalFoodSpecies,
        where: s.private == false,
        order_by: [asc: s.name, asc: s.variety]
    )
  end

  # Composable "public browse" scope: drop species an admin has marked private.
  # Applied to every consumer-facing read (feed, search, filter, directory) so a
  # private species is invisible outside the admin curation view.
  defp public_only(query), do: from(s in query, where: s.private == false)

  @doc """
  All **public** species with `:translations` preloaded, name-ordered — the
  lightweight feed for the crawlable `/foods` A–Z directory (every food linked so
  link equity reaches the ~140 detail pages the paginated feed never renders on
  first paint). Private species are excluded so they aren't linked or crawlable.
  """
  def list_species_for_directory do
    Repo.all(
      from(s in FoundementalFoodSpecies,
        where: s.private == false,
        order_by: [asc: s.name],
        preload: :translations
      )
    )
  end

  @doc """
  Search species by a free-text term matching `name`, `scientific_name`, or
  `alternative_name` (case-insensitive substring), capped at `limit` (default 20).
  Backs the article-reference species picker. A blank term returns `[]`.
  """
  def search_species(term, limit \\ 20)
  def search_species(term, _limit) when term in [nil, ""], do: []

  def search_species(term, limit) do
    Repo.all(search_species_query(term, limit))
  end

  @doc """
  Public variant of `search_species/2` — excludes species marked `private`.
  Backs the mobile API's species search (the admin article-reference picker uses
  `search_species/2`, which still sees private rows).
  """
  def search_public_species(term, limit \\ 20)
  def search_public_species(term, _limit) when term in [nil, ""], do: []

  def search_public_species(term, limit) do
    Repo.all(public_only(search_species_query(term, limit)))
  end

  defp search_species_query(term, limit) do
    like = "%#{String.trim(term)}%"

    from s in FoundementalFoodSpecies,
      where:
        ilike(s.name, ^like) or ilike(s.scientific_name, ^like) or
          ilike(s.alternative_name, ^like),
      order_by: [asc: s.name, asc: s.variety],
      limit: ^limit
  end

  @doc """
  Fetch a **public** species by its URL slug (hyphens → spaces), matching on
  `name` first and falling back to a translated name. Preloads its curated foods
  (with ingredient) and its translations. Returns `nil` when nothing matches —
  including when the match is a `private` species, so its detail page (and the
  mobile API `show`) 404 rather than leak. Mirrors
  `Mehungry.Food.Ingredients.get_ingredient_by_slug/1`.
  """
  def get_species_by_slug(slug) do
    name = String.replace(slug, "-", " ")

    species =
      Repo.one(
        from(s in FoundementalFoodSpecies,
          where: fragment("lower(?) = lower(?)", s.name, ^name) and s.private == false,
          order_by: [asc: s.variety],
          limit: 1
        )
      ) || get_species_by_translation_name(name)

    case species do
      nil ->
        nil

      species ->
        Repo.preload(species, [
          [foundemental_foods: :ingredient],
          :translations
        ])
    end
  end

  defp get_species_by_translation_name(name) do
    Repo.one(
      from(t in FoundementalFoodSpeciesTranslation,
        join: s in FoundementalFoodSpecies,
        on: s.id == t.foundemental_species_id,
        where: fragment("lower(?) = lower(?)", t.name, ^name) and s.private == false,
        select: s,
        limit: 1
      )
    )
  end

  @doc "The translated names for `(language, species)` — mirror of `find_ingredient_translation/2`."
  def find_species_translation(language_name, species_id) do
    Repo.all(
      from(t in FoundementalFoodSpeciesTranslation,
        where: t.language_name == ^language_name and t.foundemental_species_id == ^species_id,
        select: t.name
      )
    )
  end

  @doc """
  A cursor page (20) of **public** species, oldest first, ordered like the
  ingredient browse. Backs the `/foods` English feed.
  """
  def list_species_paginated(cursor_after \\ nil) do
    from(s in FoundementalFoodSpecies)
    |> public_only()
    |> paginate_species(cursor_after)
  end

  @doc "A cursor page (20) of only the **public** species that have a translation in `language_name`."
  def list_species_paginated_translated(language_name, cursor_after \\ nil) do
    translated_ids =
      from(t in FoundementalFoodSpeciesTranslation,
        where: t.language_name == ^language_name,
        select: t.foundemental_species_id
      )

    from(s in FoundementalFoodSpecies, where: s.id in subquery(translated_ids))
    |> public_only()
    |> paginate_species(cursor_after)
  end

  @doc """
  Species matching the faceted filters on `/foods`. Each facet is applied as an
  AND constraint; within a facet the ids are OR-ed (a species need only carry one).
  `opts`:

    * `:condition_compound_ids` — species must carry (non-`absent`) a compound in
      this list (the compounds a selected condition recommends to "encourage").
    * `:condition_species_ids` — species ids the condition implicates **via
      nutrients** (high in an encouraged nutrient). OR-ed with
      `:condition_compound_ids` inside the single "condition" facet, since a food is
      encouraged if it satisfies *either* the compound or the nutrient engine.
    * `:compound_ids` — species must carry a compound in this list.
    * `:query` — accent-insensitive substring on `name`/`alternative_name`.

  Empty/omitted facets are skipped. Returns species with `:translations` preloaded,
  name-ordered, capped at `:limit` (default 200).
  """
  def filter_species(opts \\ []) do
    condition_compound_ids = Keyword.get(opts, :condition_compound_ids, [])
    condition_species_ids = Keyword.get(opts, :condition_species_ids, [])
    compound_ids = Keyword.get(opts, :compound_ids, [])
    query_str = Keyword.get(opts, :query, "")
    limit = Keyword.get(opts, :limit, 200)

    from(s in FoundementalFoodSpecies, order_by: [asc: s.name, asc: s.variety], limit: ^limit)
    |> public_only()
    |> filter_species_by_condition(condition_compound_ids, condition_species_ids)
    |> filter_species_by_compounds(compound_ids)
    |> filter_species_by_name(query_str)
    |> Repo.all()
    |> Repo.preload([:translations])
  end

  # The condition facet: a species matches if it carries a non-`absent` encouraged
  # compound OR its id is in the nutrient-derived set. Both empty → no constraint.
  defp filter_species_by_condition(query, [], []), do: query

  defp filter_species_by_condition(query, compound_ids, species_ids) do
    compound_species =
      from(r in SpeciesCompoundRelationship,
        where: r.compound_id in ^compound_ids and r.relationship_type != "absent",
        select: r.foundemental_species_id
      )

    from(s in query, where: s.id in subquery(compound_species) or s.id in ^species_ids)
  end

  defp filter_species_by_compounds(query, []), do: query

  defp filter_species_by_compounds(query, compound_ids) do
    species_ids =
      from(r in SpeciesCompoundRelationship,
        where: r.compound_id in ^compound_ids and r.relationship_type != "absent",
        select: r.foundemental_species_id
      )

    from(s in query, where: s.id in subquery(species_ids))
  end

  defp filter_species_by_name(query, term) when is_binary(term) and term != "" do
    like = "%#{String.trim(term)}%"

    from(s in query,
      where:
        fragment("unaccent(?) ILIKE unaccent(?)", s.name, ^like) or
          fragment("unaccent(?) ILIKE unaccent(?)", s.alternative_name, ^like)
    )
  end

  defp filter_species_by_name(query, _term), do: query

  defp paginate_species(query, cursor_after) do
    paginate_opts =
      [cursor_fields: [{:inserted_at, :asc}, {:id, :asc}], limit: 20] ++
        if cursor_after, do: [after: cursor_after], else: []

    %{entries: entries, metadata: metadata} = Repo.paginate(query, paginate_opts)

    {Repo.preload(entries, [:translations]), metadata.after}
  end

  @doc "Species with their curated `foundemental_foods` preloaded, name-ordered."
  def list_species_with_foods do
    Repo.all(
      from s in FoundementalFoodSpecies,
        order_by: [asc: s.name, asc: s.variety],
        preload: [foundemental_foods: ^from(f in FoundementalFood, order_by: [asc: f.usda_name])]
    )
  end

  def get_species!(id), do: Repo.get!(FoundementalFoodSpecies, id)

  @doc """
  Fetch species for a list of ids in a single query, returned as an
  `%{id => species}` map (unordered). Lets callers resolve a batch of search hits
  without an N+1 of `get_species!/1`.
  """
  def species_by_ids(ids) when is_list(ids) do
    from(s in FoundementalFoodSpecies, where: s.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  Fetches a species by id with its ingredients preloaded. Mirrors the preload
  `get_species_by_slug/1` uses, so callers holding only an id can reach the
  species' curated ingredients (e.g. for nutrition + sample-recipe lookups).
  """
  def get_species_with_ingredients!(id) do
    FoundementalFoodSpecies
    |> Repo.get!(id)
    |> Repo.preload(foundemental_foods: :ingredient)
  end

  def change_species(%FoundementalFoodSpecies{} = species, attrs \\ %{}) do
    FoundementalFoodSpecies.changeset(species, attrs)
  end

  def create_species(attrs) do
    %FoundementalFoodSpecies{}
    |> FoundementalFoodSpecies.changeset(attrs)
    |> Repo.insert()
  end

  def update_species(%FoundementalFoodSpecies{} = species, attrs) do
    species
    |> FoundementalFoodSpecies.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Batch-resolves the species curated onto each of `ingredient_ids`, as a sparse
  `%{ingredient_id => %FoundementalFoodSpecies{}}` map (only the ids that map to a
  species appear — `ingredient_id` is unique in the join, so one species each).
  """
  def species_by_ingredient_ids(ingredient_ids) when is_list(ingredient_ids) do
    from(f in FoundementalFood,
      join: s in assoc(f, :species),
      where: f.ingredient_id in ^ingredient_ids,
      select: {f.ingredient_id, s}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  An emoji for each of `ingredient_ids`, as `%{ingredient_id => emoji}` (every id
  present). Locale-independent: the emoji is derived from the **English base
  name**, with a curator's species `icon` override winning when the ingredient is
  curated onto a species. At most two queries regardless of input size — the
  species join, then the base names of the ingredients not covered by a species.
  See `Mehungry.Food.SpeciesIcons`.
  """
  def ingredient_icons(ingredient_ids) when is_list(ingredient_ids) do
    ids = Enum.uniq(ingredient_ids)
    species_map = species_by_ingredient_ids(ids)

    name_map =
      ids
      |> Enum.reject(&Map.has_key?(species_map, &1))
      |> ingredient_base_names()

    Map.new(ids, fn id ->
      icon =
        case Map.get(species_map, id) do
          nil -> SpeciesIcons.default_icon(%{name: Map.get(name_map, id)})
          species -> SpeciesIcons.icon_for(species)
        end

      {id, icon}
    end)
  end

  defp ingredient_base_names([]), do: %{}

  defp ingredient_base_names(ingredient_ids) do
    from(i in Ingredient, where: i.id in ^ingredient_ids, select: {i.id, i.name})
    |> Repo.all()
    |> Map.new()
  end

  # ── Foundemental foods (join rows) ───────────────────────────────────────────

  def create_foundemental_food(attrs) do
    %FoundementalFood{}
    |> FoundementalFood.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Assigns an ingredient to a species, snapshotting `usda_name`. Idempotent-ish:
  the unique index on `ingredient_id` prevents duplicate assignment.
  """
  def assign_ingredient(species_id, ingredient_id, usda_name) do
    create_foundemental_food(%{
      foundemental_species_id: species_id,
      ingredient_id: ingredient_id,
      usda_name: usda_name
    })
  end

  @doc "The ingredient ids curated onto a species (its `foundemental_foods`)."
  def list_ingredient_ids_for_species(species_ids) when is_list(species_ids) do
    FoundementalFood
    |> where([f], f.foundemental_species_id in ^species_ids)
    |> select([f], f.ingredient_id)
    |> Repo.all()
  end

  def list_ingredient_ids_for_species(species_id) do
    FoundementalFood
    |> where([f], f.foundemental_species_id == ^species_id)
    |> select([f], f.ingredient_id)
    |> Repo.all()
  end

  @doc "The species id an ingredient is curated onto, or `nil`."
  def species_id_for_ingredient(ingredient_id) do
    Repo.one(
      from(f in FoundementalFood,
        where: f.ingredient_id == ^ingredient_id,
        select: f.foundemental_species_id
      )
    )
  end

  @doc """
  All curated ingredients with their species, ordered by species then ingredient —
  for admin selectors that record species-rollup data (e.g. compound measurements).
  Returns `[%{ingredient_id, ingredient_name, species_id, species_name}]`.
  """
  def list_curated_ingredients do
    Repo.all(
      from(f in FoundementalFood,
        join: i in assoc(f, :ingredient),
        join: s in assoc(f, :species),
        order_by: [asc: s.name, asc: i.name],
        select: %{
          ingredient_id: f.ingredient_id,
          ingredient_name: i.name,
          species_id: f.foundemental_species_id,
          species_name: s.name
        }
      )
    )
  end

  @doc "MapSet of ingredient ids already curated onto some species."
  def assigned_ingredient_ids do
    FoundementalFood
    |> select([f], f.ingredient_id)
    |> Repo.all()
    |> MapSet.new()
  end
end
