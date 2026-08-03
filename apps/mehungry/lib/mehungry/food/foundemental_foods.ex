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
    FoundementalFoodSpeciesTranslation
  }

  # ── Species ────────────────────────────────────────────────────────────────

  @doc "All species ordered by name (then variety)."
  def list_species do
    Repo.all(from s in FoundementalFoodSpecies, order_by: [asc: s.name, asc: s.variety])
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
