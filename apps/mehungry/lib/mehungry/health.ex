defmodule Mehungry.Health do
  @moduledoc """
  Health Recommendation Knowledge — a registry of health conditions and the
  dietary recommendations linking them to bioactive compounds.

  A `Condition` (Kidney Stones, IBS, Gout, …) is a shared reference entity;
  `CompoundRecommendation` links a condition to a `Mehungry.Food.Compound` as
  advice (e.g. *Kidney Stones: avoid Oxalate*, *IBS: limit FODMAP*).

  This is the **advice** layer that the "facts only" compound stack
  (`docs/food_compounds.md` §4) deliberately defers to. Its hard rule: a condition
  references a **compound**, never a species or ingredient. "Which foods should a
  kidney-stone patient avoid?" is answered by `species_for_condition/2` (the primary
  read), which **composes** this layer with `Food.SpeciesCompoundRelationship` at read
  time; `ingredients_for_condition/2` derives the ingredients strictly through those
  species. The schemas themselves stay decoupled from food data.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{Compound, FoundementalFood, RecipeIngredient, SpeciesCompoundRelationship}
  alias Mehungry.Health.{Condition, CompoundRecommendation, ConditionIdentifier}

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

  @doc "Fetch a condition by id, or `nil` if it does not exist."
  def get_condition(id), do: Repo.get(Condition, id)

  def get_condition_by_name(name), do: Repo.get_by(Condition, name: name)

  def list_conditions, do: Repo.all(from(c in Condition, order_by: [asc: c.name]))

  def list_conditions_for_presentation do
    query =
      from c in Condition,
        as: :condition,
        where:
          exists(
            from cr in CompoundRecommendation,
              where: cr.condition_id == parent_as(:condition).id
          )

    Repo.all(query)
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

  @doc "The recommendation rows for a condition, each with its `:compound` preloaded."
  def recommendations_for_condition(condition_id) do
    Repo.all(
      from(r in CompoundRecommendation,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.condition_id == ^condition_id,
        order_by: [asc: c.name],
        preload: [compound: c]
      )
    )
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
  def species_for_condition(condition_id, recommendation \\ nil) do
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

  defp maybe_filter_recommendation(query, nil), do: query

  defp maybe_filter_recommendation(query, recommendation) do
    value = to_string(recommendation)
    from(rec in query, where: rec.recommendation == ^value)
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
end
