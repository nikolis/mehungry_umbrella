defmodule Mehungry.Food.SpeciesSearch do
  @moduledoc """
  Name search over the `FoundementalFoodSpecies` registry — the species-level
  parallel of `Mehungry.Food.IngredientSearch`.

  The registry is small and admin-curated (no `search_name` column), so this is a
  straightforward accent-insensitive match on `name`/`alternative_name`, ranking
  prefix hits ahead of substring hits. `search_in_language/2` matches on the
  species' translations and returns `%{id, name}` maps, drop-in with `search/1`.
  """

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.{FoundementalFoodSpecies, FoundementalFoodSpeciesTranslation}

  @max_results 20

  @doc "Species whose name/alternative name matches `term`, prefix hits first. Translations preloaded."
  def search(term) when is_binary(term) do
    normalized = String.trim(term)

    if normalized == "" do
      []
    else
      pattern = "%#{normalized}%"
      prefix = "#{normalized}%"

      from(s in FoundementalFoodSpecies,
        where:
          fragment("unaccent(?) ILIKE unaccent(?)", s.name, ^pattern) or
            fragment("unaccent(?) ILIKE unaccent(?)", s.alternative_name, ^pattern),
        order_by: [
          desc:
            fragment(
              "CASE WHEN unaccent(?) ILIKE unaccent(?) THEN 1 ELSE 0 END",
              s.name,
              ^prefix
            ),
          asc: fragment("LENGTH(?)", s.name),
          asc: s.name,
          asc: s.variety
        ],
        limit: @max_results,
        preload: [:translations]
      )
      |> Repo.all()
    end
  end

  @doc """
  Species matched via their translations for `language_name`. Returns
  `%{id: species_id, name: translated_name}` maps (drop-in with `search/1` for
  select-style rendering).
  """
  def search_in_language(term, language_name) when is_binary(term) do
    normalized = String.trim(term)

    base =
      from(t in FoundementalFoodSpeciesTranslation,
        where: t.language_name == ^language_name,
        order_by: [
          desc:
            fragment(
              "CASE WHEN lower(unaccent(?)) = lower(unaccent(?)) THEN 1 ELSE 0 END",
              t.name,
              ^normalized
            ),
          asc: fragment("LENGTH(?)", t.name),
          asc: t.name
        ],
        limit: @max_results,
        select: %{id: t.foundemental_species_id, name: t.name}
      )

    base =
      if normalized == "" do
        base
      else
        from(t in base,
          where: fragment("unaccent(?) ILIKE unaccent(?)", t.name, ^"%#{normalized}%")
        )
      end

    Repo.all(base)
  end
end
