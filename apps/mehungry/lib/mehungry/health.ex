defmodule Mehungry.Health do
  @moduledoc """
  Health Recommendation Knowledge — a registry of health conditions and the
  dietary recommendations linking them to bioactive compounds.

  A `Condition` (Kidney Stones, IBS, Gout, …) is a shared reference entity;
  `CompoundRecommendation` links a condition to a `Mehungry.Food.Compound` as
  advice (e.g. *Kidney Stones: avoid Oxalate*, *IBS: limit FODMAP*).

  This is the **advice** layer that the "facts only" compound stack
  (`docs/food_compounds.md` §4) deliberately defers to. Its hard rule: a condition
  references a **compound**, never an ingredient. "Which foods should a
  kidney-stone patient avoid?" is answered by `ingredients_for_condition/2`, which
  **composes** this layer with `Food.IngredientCompoundRelationship` at read time —
  the schemas themselves stay decoupled from ingredient data.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{Compound, IngredientCompoundRelationship}
  alias Mehungry.Health.{Condition, CompoundRecommendation}

  # ── Condition registry ────────────────────────────────────────────────────

  def create_condition(attrs) do
    %Condition{}
    |> Condition.changeset(attrs)
    |> Repo.insert()
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

  def list_conditions_by_category(category) do
    Repo.all(
      from(c in Condition,
        where: c.category == ^category,
        order_by: [asc: c.name]
      )
    )
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
  The ingredients implicated for a condition, by composing this advice layer with
  the food-facts layer at **read time**: `condition → compound_recommendations →
  compounds → ingredient_compound_relationships → ingredients`.

  Conditions never reference ingredients directly — this join resolves the food
  through the shared compound. Pass a `recommendation` (e.g. `"avoid"` / `:avoid`)
  to filter, or `nil`/omit for every recommendation. Returns maps of
  `%{ingredient, compound, recommendation, severity, evidence_level}` so a caller
  can render "avoid Spinach (high Oxalate)".
  """
  def ingredients_for_condition(condition_id, recommendation \\ nil) do
    query =
      from(rec in CompoundRecommendation,
        join: icr in IngredientCompoundRelationship,
        on: icr.compound_id == rec.compound_id,
        join: cmp in Compound,
        on: cmp.id == rec.compound_id,
        join: ing in assoc(icr, :ingredient),
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

    query
    |> maybe_filter_recommendation(recommendation)
    |> Repo.all()
  end

  defp maybe_filter_recommendation(query, nil), do: query

  defp maybe_filter_recommendation(query, recommendation) do
    value = to_string(recommendation)
    from(rec in query, where: rec.recommendation == ^value)
  end
end
