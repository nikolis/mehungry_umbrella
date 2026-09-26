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
    SpeciesCompoundRelationship
  }

  # ── Species ────────────────────────────────────────────────────────────────

  @doc "All species ordered by name (then variety)."
  def list_species do
    Repo.all(from s in FoundementalFoodSpecies, order_by: [asc: s.name, asc: s.variety])
  end

  @doc """
  Search species by a free-text term matching `name`, `scientific_name`, or
  `alternative_name` (case-insensitive substring), capped at `limit` (default 20).
  Backs the article-reference species picker. A blank term returns `[]`.
  """
  def search_species(term, limit \\ 20)
  def search_species(term, _limit) when term in [nil, ""], do: []

  def search_species(term, limit) do
    like = "%#{String.trim(term)}%"

    Repo.all(
      from s in FoundementalFoodSpecies,
        where:
          ilike(s.name, ^like) or ilike(s.scientific_name, ^like) or
            ilike(s.alternative_name, ^like),
        order_by: [asc: s.name, asc: s.variety],
        limit: ^limit
    )
  end

  @doc """
  Fetch a species by its URL slug (hyphens → spaces), matching on `name` first and
  falling back to a translated name. Preloads its curated foods (with ingredient) and
  its translations. Returns `nil` when nothing matches. Mirrors
  `Mehungry.Food.Ingredients.get_ingredient_by_slug/1`.
  """
  def get_species_by_slug(slug) do
    name = String.replace(slug, "-", " ")

    species =
      Repo.one(
        from(s in FoundementalFoodSpecies,
          where: fragment("lower(?) = lower(?)", s.name, ^name),
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
        where: fragment("lower(?) = lower(?)", t.name, ^name),
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

  @doc "A cursor page (20) of species, oldest first, ordered like the ingredient browse."
  def list_species_paginated(cursor_after \\ nil) do
    paginate_species(from(s in FoundementalFoodSpecies), cursor_after)
  end

  @doc "A cursor page (20) of only the species that have a translation in `language_name`."
  def list_species_paginated_translated(language_name, cursor_after \\ nil) do
    translated_ids =
      from(t in FoundementalFoodSpeciesTranslation,
        where: t.language_name == ^language_name,
        select: t.foundemental_species_id
      )

    from(s in FoundementalFoodSpecies, where: s.id in subquery(translated_ids))
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
