defmodule Mehungry.Food.Compounds do
  @moduledoc """
  Food Compound Knowledge — a registry of bioactive / chemical compounds and the
  scientific facts linking them to ingredients.

  A `Compound` (oxalate, lectin, phytate, histamine, polyphenol, FODMAP compound,
  purine, salicylate, or other bioactive) is a shared reference entity with its
  own chemical identity; `IngredientCompoundRelationship` links a compound to an
  ingredient as a fact (e.g. *Spinach contains Oxalate*).

  Like `Mehungry.Food.Enrichment`, this sidecar is keyed by `ingredient_id`/
  `compound_id` and is never read or written by the USDA ingestion/reconciliation
  path. It represents **scientific facts only** — never recommendations or advice.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Compound,
    CompoundIdentifier,
    IngredientCompoundRelationship
  }

  # ── Compound registry ────────────────────────────────────────────────────

  def create_compound(attrs) do
    %Compound{}
    |> Compound.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Find-or-create a compound by its natural key `name`, backed by the unique index."
  def upsert_compound(attrs) do
    attrs
    |> create_compound()
    |> case do
      {:ok, compound} ->
        {:ok, compound}

      {:error, _changeset} ->
        name = attrs[:name] || attrs["name"]
        {:ok, Repo.one!(from(c in Compound, where: c.name == ^name))}
    end
  end

  @doc """
  Additively enrich an existing compound row (synonyms unioned, structural
  `properties` merged with the *existing* value winning, `description` back-filled
  when blank). `name` and `compound_type` are never overwritten.

  Cross-database identity is not touched here — that flows through
  `upsert_compound_identifier/1`. Used by `Mehungry.Chemistry.Resolver` when it
  re-resolves a compound it already holds.
  """
  def enrich_compound(%Compound{} = compound, attrs) do
    attrs = Map.new(attrs)

    compound
    |> Compound.changeset(%{
      synonyms: merge_synonyms(compound.synonyms, attrs[:synonyms]),
      properties: Map.merge(attrs[:properties] || %{}, compound.properties || %{}),
      description: backfill(compound.description, attrs[:description])
    })
    |> Repo.update()
  end

  defp merge_synonyms(existing, incoming) do
    ((existing || []) ++ (incoming || [])) |> Enum.uniq()
  end

  # Keep the current value unless it is blank, in which case take the incoming one.
  defp backfill(current, incoming) when current in [nil, ""], do: incoming
  defp backfill(current, _incoming), do: current

  # ── Cross-database identifiers (the normalized identity model) ─────────────

  @doc "The compound bearing `identifier` in `namespace`, or `nil`."
  def get_compound_by_identifier(namespace, identifier) do
    Repo.one(
      from(c in Compound,
        join: ci in CompoundIdentifier,
        on: ci.compound_id == c.id,
        where: ci.namespace == ^namespace and ci.identifier == ^to_string(identifier)
      )
    )
  end

  @doc """
  Insert or update a compound's identifier row, keyed on the natural
  `(namespace, identifier)` — so the same external id always resolves to one
  compound. `attrs` carries `:compound_id`, `:namespace`, `:identifier`, and
  optionally `:is_primary` / `:source`.
  """
  def upsert_compound_identifier(attrs) do
    %CompoundIdentifier{}
    |> CompoundIdentifier.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:namespace, :identifier]
    )
  end

  @doc "All cross-database identifiers for a compound."
  def list_compound_identifiers(compound_id) do
    Repo.all(
      from(ci in CompoundIdentifier,
        where: ci.compound_id == ^compound_id,
        order_by: [asc: ci.namespace]
      )
    )
  end

  def get_compound!(id), do: Repo.get!(Compound, id)

  @doc "Fetch compounds by a list of ids (name + synonyms), for extraction/lookup."
  def get_compounds_by_ids([]), do: []
  def get_compounds_by_ids(ids), do: Repo.all(from(c in Compound, where: c.id in ^ids))

  def get_compound_by_name(name), do: Repo.get_by(Compound, name: name)

  def list_compounds, do: Repo.all(from(c in Compound, order_by: [asc: c.name]))

  def list_compounds_by_type(compound_type) do
    Repo.all(
      from(c in Compound,
        where: c.compound_type == ^compound_type,
        order_by: [asc: c.name]
      )
    )
  end

  # ── Ingredient ↔ compound relationships (scientific facts) ────────────────

  def link_compound(attrs) do
    %IngredientCompoundRelationship{}
    |> IngredientCompoundRelationship.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Insert or update a relationship, keyed on
  `(ingredient_id, compound_id, relationship_type, source)`.
  """
  def upsert_compound_relationship(attrs) do
    %IngredientCompoundRelationship{}
    |> IngredientCompoundRelationship.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:ingredient_id, :compound_id, :relationship_type, :source]
    )
  end

  def delete_compound_relationship(%IngredientCompoundRelationship{} = relationship),
    do: Repo.delete(relationship)

  @doc "All compounds linked to an ingredient (each with its relationship preloaded)."
  def list_compounds_for_ingredient(ingredient_id) do
    Repo.all(
      from(r in IngredientCompoundRelationship,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.ingredient_id == ^ingredient_id,
        order_by: [asc: c.name],
        preload: [compound: c]
      )
    )
    |> Enum.map(& &1.compound)
  end

  @doc """
  Compounds an ingredient is asserted to *contain* — every relationship except
  `absent`, deduped. This is what the literature crawler reads to build targeted
  search terms, so a negative (`absent`) fact must never leak in as a term.
  """
  def list_positive_compounds_for_ingredient(ingredient_id) do
    Repo.all(
      from(r in IngredientCompoundRelationship,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.ingredient_id == ^ingredient_id and r.relationship_type != "absent",
        distinct: c.id,
        order_by: [asc: c.id],
        select: c
      )
    )
    |> Enum.sort_by(& &1.name)
  end

  @doc "All ingredients linked to a compound (via the relationship rows)."
  def list_ingredients_for_compound(compound_id) do
    Repo.all(
      from(r in IngredientCompoundRelationship,
        where: r.compound_id == ^compound_id,
        preload: [:ingredient]
      )
    )
    |> Enum.map(& &1.ingredient)
  end

  @doc "The raw relationship rows for an ingredient, compound preloaded."
  def list_compound_relationships(ingredient_id) do
    Repo.all(
      from(r in IngredientCompoundRelationship,
        where: r.ingredient_id == ^ingredient_id,
        order_by: [asc: r.id],
        preload: [:compound]
      )
    )
  end

  @doc """
  Upsert a compound and link it to an ingredient in one call — the "Spinach
  contains Oxalate" convenience. `rel_attrs` supplies `relationship_type`,
  `source`, `confidence`, `notes`; `ingredient_id`/`compound_id` are injected.
  """
  def add_compound_to_ingredient(ingredient_id, compound_attrs, rel_attrs) do
    with {:ok, compound} <- upsert_compound(compound_attrs) do
      rel_attrs
      |> Map.new()
      |> Map.merge(%{ingredient_id: ingredient_id, compound_id: compound.id})
      |> upsert_compound_relationship()
    end
  end
end
