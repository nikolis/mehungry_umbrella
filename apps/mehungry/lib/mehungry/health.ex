defmodule Mehungry.Health do
  @moduledoc """
  Health Recommendation Knowledge — a registry of health conditions and the
  dietary recommendations linking them to bioactive compounds.

  A `Condition` (Kidney Stones, IBS, Gout, …) is a shared reference entity;
  `CompoundRecommendation` links a condition to a `Mehungry.Food.Compound` as
  advice (e.g. *Kidney Stones: avoid Oxalate*, *IBS: limit FODMAP*).

  This is the **advice** layer that the "facts only" compound stack
  (`docs/science/food_compounds.md` §4) deliberately defers to. Its hard rule: a condition
  references a **compound**, never a species or ingredient. "Which foods should a
  kidney-stone patient avoid?" is answered by `species_for_condition/2` (the primary
  read), which **composes** this layer with `Food.SpeciesCompoundRelationship` at read
  time; `ingredients_for_condition/2` derives the ingredients strictly through those
  species. The schemas themselves stay decoupled from food data.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Compound,
    CompoundTranslation,
    FoundementalFood,
    FoundementalFoodSpeciesTranslation,
    Recipe,
    RecipeIngredient,
    SpeciesCompoundRelationship
  }

  alias Mehungry.Health.{
    Condition,
    CompoundRecommendation,
    ConditionIdentifier,
    ConditionTranslation
  }

  alias Mehungry.Languages.Locale

  # Read-through cache for the editorial, shared-safe condition-page reads. These
  # rows are curated (at /professional/health) and vary only by entity id + language,
  # so a shared cache is safe; a moderate TTL lets admin edits surface without
  # having to bust every write path. Namespaced tuple keys mirror Recipes.get_recipe!/1.
  @cache_key_ns Mehungry.Health
  @cache_ttl :timer.hours(1)

  # ── Condition registry ────────────────────────────────────────────────────

  def create_condition(attrs) do
    %Condition{}
    |> Condition.changeset(attrs)
    |> Repo.insert()
  end

  @doc "A changeset for a condition — for admin forms."
  def change_condition(condition \\ %Condition{}, attrs \\ %{}) do
    Condition.changeset(condition, attrs)
  end

  @doc "Delete a condition by id; its `compound_recommendations` cascade (`on_delete`)."
  def delete_condition(id) do
    case Repo.get(Condition, id) do
      nil -> {:error, :not_found}
      condition -> Repo.delete(condition)
    end
  end

  @doc "Find-or-create a condition by its natural key `name`, backed by the unique index."
  def upsert_condition(attrs) do
    attrs
    |> create_condition()
    |> case do
      {:ok, condition} ->
        {:ok, condition}

      {:error, _changeset} ->
        name = attrs[:name] || attrs["name"]
        {:ok, Repo.one!(from(c in Condition, where: c.name == ^name))}
    end
  end

  def get_condition!(id), do: Repo.get!(Condition, id)

  @doc """
  Fetch a condition by id, or `nil` if it does not exist. Pass a `language`
  (ISO locale, e.g. `"el"`) to overlay its `condition_translations` name/description
  (per-field fallback to the base record); `nil`/`"en"` returns the base record.
  """
  def get_condition(id, language \\ nil) do
    key = {@cache_key_ns, {:condition, id, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        case Repo.get(Condition, id) do
          nil ->
            nil

          condition ->
            localized = localize_condition(condition, language)
            Cachex.put(:health_cache, key, localized, ttl: @cache_ttl)
            localized
        end

      {:ok, cached} ->
        cached
    end
  end

  def get_condition_by_name(name), do: Repo.get_by(Condition, name: name)

  def list_conditions, do: Repo.all(from(c in Condition, order_by: [asc: c.name]))

  def list_conditions_for_presentation(language \\ nil) do
    query =
      from c in Condition,
        as: :condition,
        where:
          exists(
            from cr in CompoundRecommendation,
              where: cr.condition_id == parent_as(:condition).id
          )

    query
    |> Repo.all()
    |> localize_conditions(language)
  end

  def list_conditions_by_category(category) do
    Repo.all(
      from(c in Condition,
        where: c.category == ^category,
        order_by: [asc: c.name]
      )
    )
  end

  # ── Condition cross-database identifiers (mesh/icd…) ──────────────────────
  # Mirror of the `Food.Compounds` identifier API — the disease-resolution seam.

  @doc "Fetch the condition owning `(namespace, identifier)`, or nil."
  def get_condition_by_identifier(namespace, identifier) do
    Repo.one(
      from(c in Condition,
        join: i in ConditionIdentifier,
        on: i.condition_id == c.id,
        where: i.namespace == ^namespace and i.identifier == ^identifier
      )
    )
  end

  @doc "Insert-or-update a condition identifier, keyed on `(namespace, identifier)`."
  def upsert_condition_identifier(attrs) do
    %ConditionIdentifier{}
    |> ConditionIdentifier.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:condition_id, :is_primary, :source, :updated_at]},
      conflict_target: [:namespace, :identifier]
    )
  end

  def list_condition_identifiers(condition_id) do
    Repo.all(from(i in ConditionIdentifier, where: i.condition_id == ^condition_id))
  end

  # ── Condition ↔ compound recommendations (dietary advice) ─────────────────

  def create_recommendation(attrs) do
    %CompoundRecommendation{}
    |> CompoundRecommendation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Insert or update a recommendation, keyed on `(condition_id, compound_id, source)`.
  Re-asserting from the same source overwrites (a correction); a different source is
  kept as a distinct row.
  """
  def upsert_recommendation(attrs) do
    %CompoundRecommendation{}
    |> CompoundRecommendation.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:condition_id, :compound_id, :source]
    )
  end

  def delete_recommendation(%CompoundRecommendation{} = recommendation),
    do: Repo.delete(recommendation)

  def get_recommendation!(id), do: Repo.get!(CompoundRecommendation, id)

  @doc """
  The recommendation rows for a condition, each with its `:compound` preloaded.
  Pass a `language` to overlay the compound's `compound_translations` name.
  """
  def recommendations_for_condition(condition_id, language \\ nil) do
    key = {@cache_key_ns, {:recommendations, condition_id, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        result = do_recommendations_for_condition(condition_id, language)
        Cachex.put(:health_cache, key, result, ttl: @cache_ttl)
        result

      {:ok, cached} ->
        cached
    end
  end

  defp do_recommendations_for_condition(condition_id, language) do
    Repo.all(
      from(r in CompoundRecommendation,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.condition_id == ^condition_id,
        order_by: [asc: c.name],
        preload: [compound: c]
      )
    )
    |> localize_recommendation_compounds(language)
  end

  @doc "The recommendation rows for a compound, each with its `:condition` preloaded."
  def recommendations_for_compound(compound_id) do
    Repo.all(
      from(r in CompoundRecommendation,
        join: c in Condition,
        on: c.id == r.condition_id,
        where: r.compound_id == ^compound_id,
        order_by: [asc: c.name],
        preload: [condition: c]
      )
    )
  end

  @doc """
  Upsert a condition and link it to an existing compound in one call — the
  "Kidney Stones: avoid Oxalate" convenience. `rec_attrs` supplies
  `recommendation`, `severity`, `evidence_level`, `source`, `notes`;
  `condition_id`/`compound_id` are injected. Mirrors
  `Mehungry.Food.add_compound_to_ingredient/3`.
  """
  def add_recommendation(condition_id, compound_id, rec_attrs)
      when is_integer(condition_id) do
    rec_attrs
    |> Map.new()
    |> Map.merge(%{condition_id: condition_id, compound_id: compound_id})
    |> upsert_recommendation()
  end

  def add_recommendation(condition_attrs, compound_id, rec_attrs) do
    with {:ok, condition} <- upsert_condition(condition_attrs) do
      add_recommendation(condition.id, compound_id, rec_attrs)
    end
  end

  # ── Derived cross-layer read (composition, not schema coupling) ───────────

  @doc """
  The **food species** implicated for a condition, composing this advice layer with
  the species-facts layer at **read time**: `condition → compound_recommendations →
  compounds → species_compound_relationships → species`.

  Conditions never reference species (or ingredients) directly — this join resolves
  the food through the shared compound. Pass a `recommendation` (e.g. `"avoid"` /
  `:avoid`) to filter, or `nil`/omit for every recommendation. Returns maps of
  `%{species, compound, recommendation, severity, evidence_level}` so a caller can
  render "avoid Spinach (high Oxalate)".
  """
  def species_for_condition(condition_id, recommendation \\ nil, language \\ nil) do
    key = {@cache_key_ns, {:species, condition_id, recommendation, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        result = do_species_for_condition(condition_id, recommendation, language)
        Cachex.put(:health_cache, key, result, ttl: @cache_ttl)
        result

      {:ok, cached} ->
        cached
    end
  end

  defp do_species_for_condition(condition_id, recommendation, language) do
    from(rec in CompoundRecommendation,
      join: scr in SpeciesCompoundRelationship,
      on: scr.compound_id == rec.compound_id,
      join: cmp in Compound,
      on: cmp.id == rec.compound_id,
      join: sp in assoc(scr, :species),
      where: rec.condition_id == ^condition_id,
      order_by: [asc: sp.name, asc: cmp.name],
      select: %{
        species: sp,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity,
        evidence_level: rec.evidence_level
      }
    )
    |> maybe_filter_recommendation(recommendation)
    |> Repo.all()
    |> localize_species_rows(language)
  end

  @doc """
  The dietary advice implicated for a **food species** — the inverse of
  `species_for_condition/2`: `species → species_compound_relationships → compounds →
  compound_recommendations → conditions`. Returns maps of
  `%{compound, condition, recommendation, severity, evidence_level, source}` so a
  species page can render "Oxalate — avoid for Kidney Stones (high)". Ordered by
  condition then compound.
  """
  def recommendations_for_species(species_id) do
    Repo.all(
      from(scr in SpeciesCompoundRelationship,
        join: rec in CompoundRecommendation,
        on: rec.compound_id == scr.compound_id,
        join: cmp in Compound,
        on: cmp.id == scr.compound_id,
        join: cond in Condition,
        on: cond.id == rec.condition_id,
        where: scr.foundemental_species_id == ^species_id,
        order_by: [asc: cond.name, asc: cmp.name],
        select: %{
          compound: cmp,
          condition: cond,
          recommendation: rec.recommendation,
          severity: rec.severity,
          evidence_level: rec.evidence_level,
          source: rec.source
        }
      )
    )
    # A species can carry a compound via several relationship rows; collapse to one
    # advice line per (condition, compound, recommendation).
    |> Enum.uniq_by(&{&1.condition.id, &1.compound.id, &1.recommendation})
  end

  @doc """
  The ingredients implicated for a condition — a convenience **derived strictly
  through species**: `condition → compound → species → (species' ingredients)`. There
  is no condition↔ingredient or fact↔ingredient link; ingredients are only reachable
  via the `FoundementalFoodSpecies` that carries the compound. Same filtering + shape
  as `species_for_condition/2`, but with `ingredient` in place of `species`.
  """
  def ingredients_for_condition(condition_id, recommendation \\ nil) do
    from(rec in CompoundRecommendation,
      join: scr in SpeciesCompoundRelationship,
      on: scr.compound_id == rec.compound_id,
      join: cmp in Compound,
      on: cmp.id == rec.compound_id,
      join: ff in FoundementalFood,
      on: ff.foundemental_species_id == scr.foundemental_species_id,
      join: ing in assoc(ff, :ingredient),
      where: rec.condition_id == ^condition_id,
      order_by: [asc: ing.name, asc: cmp.name],
      select: %{
        ingredient: ing,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity,
        evidence_level: rec.evidence_level
      }
    )
    |> maybe_filter_recommendation(recommendation)
    |> Repo.all()
  end

  @discouraged_recommendations ~w(avoid limit caution)

  @doc """
  Encouraged and discouraged **ingredients** for a condition — a convenience over
  `ingredients_for_condition/2` for recipe generation. Encouraged ingredients carry
  a compound the condition recommends to `"encourage"`; discouraged ones carry a
  compound recommended to `"avoid"`, `"limit"`, or `"caution"`. Both lists are the
  bare `Ingredient` structs, deduped by id.

  Returns `%{encouraged: [ingredient], discouraged: [ingredient]}`.
  """
  def ingredient_guidance_for_condition(condition_id) do
    discouraged =
      @discouraged_recommendations
      |> Enum.flat_map(&ingredients_for_condition(condition_id, &1))
      |> Enum.map(& &1.ingredient)
      |> Enum.uniq_by(& &1.id)

    discouraged_ids = MapSet.new(discouraged, & &1.id)

    # An ingredient whose species carries both an "encourage" and an
    # "avoid"/"limit"/"caution" compound would otherwise land in both lists and
    # be seeded as primary AND avoid — a "build around X" / "never use X"
    # contradiction that makes the avoid-guard reject every recipe. Keep such
    # contested ingredients as discouraged only.
    encouraged =
      condition_id
      |> ingredients_for_condition("encourage")
      |> Enum.map(& &1.ingredient)
      |> Enum.uniq_by(& &1.id)
      |> Enum.reject(&MapSet.member?(discouraged_ids, &1.id))

    %{encouraged: encouraged, discouraged: discouraged}
  end

  defp maybe_filter_recommendation(query, nil), do: query

  defp maybe_filter_recommendation(query, recommendation) do
    value = to_string(recommendation)
    from(rec in query, where: rec.recommendation == ^value)
  end

  # ── DB-content localization ───────────────────────────────────────────────
  # Condition/compound/species names + descriptions carry per-language rows in
  # their `*_translation` tables. A locale maps to *several* `language_name` codes
  # (`Locale.data_codes/1`: the canonical ISO code plus legacy aliases, e.g.
  # `"el" => ["el", "Gr"]`) — species/ingredient rows in particular predate the
  # ISO migration and are stored under `"Gr"`, so a query on `"el"` alone silently
  # finds nothing. These helpers batch-load across *all* the locale's codes (no
  # N+1), preferring the canonical ISO row when an entity has both, and overlay
  # them onto the base records with per-field fallback. `nil`/`"en"` is a no-op.

  defp translatable_language?(language), do: language not in [nil, "", "en"]

  defp localize_condition(condition, language) do
    [condition] |> localize_conditions(language) |> hd()
  end

  defp localize_conditions(conditions, language) do
    if translatable_language?(language) do
      codes = Locale.data_codes(language)
      ids = Enum.map(conditions, & &1.id)

      by_id =
        from(t in ConditionTranslation,
          where: t.condition_id in ^ids and t.language_name in ^codes
        )
        |> Repo.all()
        |> best_by_id(codes, & &1.condition_id)

      Enum.map(conditions, fn c ->
        case by_id[c.id] do
          nil -> c
          t -> %{c | name: t.name || c.name, description: t.description || c.description}
        end
      end)
    else
      conditions
    end
  end

  defp localize_recommendation_compounds(rows, language) do
    if translatable_language?(language) do
      names = compound_translation_names(Enum.map(rows, & &1.compound.id), language)
      Enum.map(rows, &%{&1 | compound: apply_compound_name(&1.compound, names)})
    else
      rows
    end
  end

  defp localize_species_rows(rows, language) do
    if translatable_language?(language) do
      compound_names = compound_translation_names(Enum.map(rows, & &1.compound.id), language)
      species_names = species_translation_names(Enum.map(rows, & &1.species.id), language)

      Enum.map(rows, fn row ->
        %{
          row
          | compound: apply_compound_name(row.compound, compound_names),
            species: apply_species_name(row.species, species_names)
        }
      end)
    else
      rows
    end
  end

  defp compound_translation_names([], _language), do: %{}

  defp compound_translation_names(ids, language) do
    codes = Locale.data_codes(language)

    from(t in CompoundTranslation,
      where: t.compound_id in ^ids and t.language_name in ^codes and not is_nil(t.name)
    )
    |> Repo.all()
    |> best_by_id(codes, & &1.compound_id)
    |> Map.new(fn {id, t} -> {id, t.name} end)
  end

  defp species_translation_names([], _language), do: %{}

  defp species_translation_names(ids, language) do
    codes = Locale.data_codes(language)

    from(t in FoundementalFoodSpeciesTranslation,
      where:
        t.foundemental_species_id in ^ids and t.language_name in ^codes and not is_nil(t.name)
    )
    |> Repo.all()
    |> best_by_id(codes, & &1.foundemental_species_id)
    |> Map.new(fn {id, t} -> {id, t.name} end)
  end

  # Collapses translation rows to one per entity id, preferring the row whose
  # `language_name` ranks earliest in `codes` (index 0 = canonical ISO code) when
  # an entity carries both an ISO and a legacy-alias row.
  defp best_by_id(rows, codes, id_fun) do
    rank = codes |> Enum.with_index() |> Map.new()

    rows
    |> Enum.reduce(%{}, fn row, acc ->
      id = id_fun.(row)
      r = Map.get(rank, row.language_name, length(codes))

      case acc do
        %{^id => {best, _}} when best <= r -> acc
        _ -> Map.put(acc, id, {r, row})
      end
    end)
    |> Map.new(fn {id, {_r, row}} -> {id, row} end)
  end

  defp apply_compound_name(compound, names) do
    case names[compound.id] do
      nil -> compound
      name -> %{compound | name: name}
    end
  end

  defp apply_species_name(species, names) do
    case names[species.id] do
      nil -> species
      name -> %{species | name: name}
    end
  end

  @doc """
  Condition badges implicated for a set of recipes, restricted to the given
  opted-in `condition_ids`. Walks `recipe_ingredients → ingredient →
  foundemental_foods → species_compound_relationships → compound_recommendations
  → conditions`, the same composition as `recommendations_for_species/1` but
  anchored on recipes.

  Returns `%{recipe_id => [%{condition, compound, recommendation, severity}]}`,
  deduped per `{recipe_id, condition_id, compound_id, recommendation}`. Recipes
  with no flagged compound are absent from the map. Returns `%{}` immediately
  when either list is empty, so callers can pass a non-opted-in user's empty set
  without hitting the database.
  """
  def flags_for_recipes([], _condition_ids), do: %{}
  def flags_for_recipes(_recipe_ids, []), do: %{}

  def flags_for_recipes(recipe_ids, condition_ids) do
    from(ri in RecipeIngredient,
      join: ff in FoundementalFood,
      on: ff.ingredient_id == ri.ingredient_id,
      join: scr in SpeciesCompoundRelationship,
      on: scr.foundemental_species_id == ff.foundemental_species_id,
      join: rec in CompoundRecommendation,
      on: rec.compound_id == scr.compound_id,
      join: cmp in Compound,
      on: cmp.id == scr.compound_id,
      join: cond in Condition,
      on: cond.id == rec.condition_id,
      where:
        ri.recipe_id in ^recipe_ids and rec.condition_id in ^condition_ids and
          scr.relationship_type != "absent",
      order_by: [asc: cond.name, asc: cmp.name],
      select: %{
        recipe_id: ri.recipe_id,
        condition: cond,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity
      }
    )
    |> Repo.all()
    |> Enum.uniq_by(&{&1.recipe_id, &1.condition.id, &1.compound.id, &1.recommendation})
    |> Enum.group_by(& &1.recipe_id, &Map.delete(&1, :recipe_id))
  end

  @doc """
  Convenience wrapper over `flags_for_recipes/2` for a single recipe. Returns
  the flag list (possibly empty).
  """
  def flags_for_recipe(recipe_id, condition_ids) do
    flags_for_recipes([recipe_id], condition_ids)
    |> Map.get(recipe_id, [])
  end

  @doc """
  Builds (but does not run) an Ecto `Recipe` query restricted to recipes that
  are **good for** the given conditions — i.e. recipes whose ingredients carry a
  compound the condition recommends to `"encourage"`. Walks the same chain as
  `flags_for_recipes/2` (`recipe_ingredients → ingredient → foundemental_foods →
  species_compound_relationships → compound_recommendations`) as a recipe-id
  subquery so the returned top-level `Recipe` query stays compatible with the
  cursor paginator (`Food.list_recipes/3`, `cursor_fields:
  [{:inserted_at, :asc}, {:id, :asc}]`) and can be further composed with the
  full-text search (`Mehungry.Search.RecipeSearch.run/2`).

  Returns the empty-image-filtered `Recipe` query when `condition_ids` is empty,
  matching the default browse behavior.
  """
  def recipes_for_conditions_query([]), do: from(r in Recipe, where: not is_nil(r.image_url))

  def recipes_for_conditions_query(condition_ids) do
    encouraged_ids =
      from(e in subquery(encouraged_recipe_ids_query(condition_ids)), select: e.recipe_id)

    from(r in Recipe,
      where: not is_nil(r.image_url),
      where: r.id in subquery(encouraged_ids)
    )
  end

  @doc """
  Builds (but does not run) the browse `Recipe` query **prioritized** for the
  given conditions: the full image-filtered catalog, ordered so recipes
  encouraged for the conditions (via `recipes_for_conditions_query/1`'s chain)
  sort to the top, then everything else, each group by `inserted_at`/`id`. This
  is the "prioritize, don't restrict" ordering behind the browse condition
  filter — nothing is hidden, encouraged recipes just lead.

  Because the priority is a computed expression (not a plain column), the
  resulting query is **offset-paginated** via `Food.list_recipes_page/4` rather
  than the cursor paginator. It stays composable with the full-text search
  (`Mehungry.Search.RecipeSearch.run/2`), which appends a rank `order_by` after
  this one, so the priority stays primary and relevance breaks ties.

  Returns the plain image-filtered `Recipe` query when `condition_ids` is empty.
  """
  def recipes_prioritized_for_conditions_query([]),
    do: from(r in Recipe, where: not is_nil(r.image_url), order_by: [asc: r.inserted_at, asc: r.id])

  def recipes_prioritized_for_conditions_query(condition_ids) do
    encouraged_ids = encouraged_recipe_ids_query(condition_ids)

    from(r in Recipe,
      left_join: e in subquery(encouraged_ids),
      on: e.recipe_id == r.id,
      where: not is_nil(r.image_url),
      # `e.recipe_id IS NULL` is false (0) for encouraged recipes, true (1) for
      # the rest → ascending puts encouraged first.
      order_by: [asc: fragment("? IS NULL", e.recipe_id), asc: r.inserted_at, asc: r.id]
    )
  end

  # Distinct recipe-id subquery for recipes whose ingredients carry a compound
  # the given conditions recommend to "encourage". Shared by the "encouraged"
  # (`recipes_for_conditions_query/1`) and "prioritized" browse queries so both
  # agree on the same set; `distinct` keeps the prioritized query's left join
  # from multiplying recipe rows.
  defp encouraged_recipe_ids_query(condition_ids) do
    from(ri in RecipeIngredient,
      join: ff in FoundementalFood,
      on: ff.ingredient_id == ri.ingredient_id,
      join: scr in SpeciesCompoundRelationship,
      on: scr.foundemental_species_id == ff.foundemental_species_id,
      join: rec in CompoundRecommendation,
      on: rec.compound_id == scr.compound_id,
      where:
        rec.condition_id in ^condition_ids and
          rec.recommendation == "encourage" and
          scr.relationship_type != "absent",
      distinct: true,
      select: %{recipe_id: ri.recipe_id}
    )
  end

  @doc """
  Condition badges implicated for a set of **ingredients**, restricted to the
  given opted-in `condition_ids`. The ingredient-anchored sibling of
  `flags_for_recipes/2`: walks `ingredient → foundemental_foods →
  species_compound_relationships → compound_recommendations → conditions`.

  Returns `%{ingredient_id => [%{condition, compound, recommendation, severity}]}`,
  deduped per `{ingredient_id, condition_id, compound_id, recommendation}`.
  Ingredients with no flagged compound are absent from the map. Returns `%{}`
  immediately when either list is empty, so callers can pass a non-opted-in
  user's empty set without hitting the database.
  """
  def flags_for_ingredients([], _condition_ids), do: %{}
  def flags_for_ingredients(_ingredient_ids, []), do: %{}

  def flags_for_ingredients(ingredient_ids, condition_ids) do
    from(ff in FoundementalFood,
      join: scr in SpeciesCompoundRelationship,
      on: scr.foundemental_species_id == ff.foundemental_species_id,
      join: rec in CompoundRecommendation,
      on: rec.compound_id == scr.compound_id,
      join: cmp in Compound,
      on: cmp.id == scr.compound_id,
      join: cond in Condition,
      on: cond.id == rec.condition_id,
      where:
        ff.ingredient_id in ^ingredient_ids and rec.condition_id in ^condition_ids and
          scr.relationship_type != "absent",
      order_by: [asc: cond.name, asc: cmp.name],
      select: %{
        ingredient_id: ff.ingredient_id,
        condition: cond,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity
      }
    )
    |> Repo.all()
    |> Enum.uniq_by(&{&1.ingredient_id, &1.condition.id, &1.compound.id, &1.recommendation})
    |> Enum.group_by(& &1.ingredient_id, &Map.delete(&1, :ingredient_id))
  end

  @doc """
  Convenience wrapper over `flags_for_ingredients/2` for a single ingredient.
  Returns the flag list (possibly empty).
  """
  def flags_for_ingredient(ingredient_id, condition_ids) do
    flags_for_ingredients([ingredient_id], condition_ids)
    |> Map.get(ingredient_id, [])
  end
end
