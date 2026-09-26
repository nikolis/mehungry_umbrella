defmodule Mehungry.Food.SpeciesCompounds do
  @moduledoc """
  Curated `FoundementalFoodSpecies`↔`Compound` facts — the species-keyed fact layer
  that stage-4 promotion writes and `Mehungry.Health` reads. The species-level
  successor of the ingredient relationship functions in `Mehungry.Food.Compounds`.

  Facts only: a row asserts *Apricot contains Flavonoids*, never advice. Conditions
  in `Health` resolve to species through these rows; the implicated ingredients are
  derived from the species, never linked directly.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{
    Compound,
    SpeciesCompoundRelationship,
    SpeciesCompoundRelationshipStudy
  }

  alias Mehungry.Literature.ScientificStudy

  @doc "Find-or-refresh a curated species↔compound fact on its natural key."
  def upsert_species_relationship(attrs) do
    %SpeciesCompoundRelationship{}
    |> SpeciesCompoundRelationship.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:foundemental_species_id, :compound_id, :relationship_type, :source]
    )
  end

  def delete_species_relationship(%SpeciesCompoundRelationship{} = rel), do: Repo.delete(rel)

  @doc "All compounds linked to a species (each with its relationship preloaded)."
  def list_compounds_for_species(species_id) do
    Repo.all(
      from(r in SpeciesCompoundRelationship,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.foundemental_species_id == ^species_id,
        order_by: [asc: c.name],
        preload: [compound: c]
      )
    )
    |> Enum.map(& &1.compound)
  end

  @doc """
  Compounds a species is asserted to *contain* — every relationship except `absent`,
  deduped. Read directly from the species facts. This is what the literature crawler
  reads to build targeted search terms, so a negative (`absent`) fact must never leak
  in as a term.
  """
  def list_positive_compounds_for_species(species_id) do
    Repo.all(
      from(r in SpeciesCompoundRelationship,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.foundemental_species_id == ^species_id and r.relationship_type != "absent",
        distinct: c.id,
        order_by: [asc: c.id],
        select: c
      )
    )
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Distinct dietary-relevant compounds linked to at least one species by a
  non-`absent` relationship — the compounds worth offering as a facet on the
  `/foods` filter (filtering by a compound no species carries would only ever yield
  nothing). Name-ordered.
  """
  def list_linked_compounds do
    Repo.all(
      from(c in Compound,
        as: :compound,
        where:
          c.dietary_relevance != "non_dietary" and
            exists(
              from(r in SpeciesCompoundRelationship,
                where:
                  r.compound_id == parent_as(:compound).id and r.relationship_type != "absent"
              )
            ),
        order_by: [asc: c.name]
      )
    )
  end

  @doc "All species linked to a compound (via the relationship rows)."
  def list_species_for_compound(compound_id) do
    Repo.all(
      from(r in SpeciesCompoundRelationship,
        where: r.compound_id == ^compound_id,
        preload: [:species]
      )
    )
    |> Enum.map(& &1.species)
  end

  @doc "The raw relationship rows for a species, compound preloaded."
  def list_species_relationships(species_id) do
    Repo.all(
      from(r in SpeciesCompoundRelationship,
        where: r.foundemental_species_id == ^species_id,
        order_by: [asc: r.id],
        preload: [:compound]
      )
    )
  end

  @doc """
  The reference studies (PubMed papers) cited by a single species↔compound
  relationship, id-ascending. Loaded on demand (e.g. when the evidence modal is
  opened) so the species page's initial paint carries no study rows.
  """
  def list_relationship_studies(relationship_id) do
    Repo.all(
      from(rs in SpeciesCompoundRelationshipStudy,
        join: s in ScientificStudy,
        on: s.id == rs.study_id,
        where: rs.relationship_id == ^relationship_id,
        order_by: [asc: s.id],
        select: s
      )
    )
  end

  @doc "Total number of curated species↔compound relationships."
  def count_relationships, do: Repo.aggregate(SpeciesCompoundRelationship, :count)

  @doc "A page of curated species relationships, newest first, species + compound preloaded."
  def list_relationships_page(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(r in SpeciesCompoundRelationship,
        order_by: [desc: r.id],
        preload: [:species, :compound],
        limit: ^limit,
        offset: ^offset
      )
    )
  end
end
