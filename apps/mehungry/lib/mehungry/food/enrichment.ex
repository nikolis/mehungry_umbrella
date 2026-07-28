defmodule Mehungry.Food.Enrichment do
  @moduledoc """
  Scientific-enrichment sidecar over the ingredient pool.

  Attaches four kinds of enrichment to an `Ingredient` without ever touching the
  USDA ingestion path: bioactive/compound measures
  (`IngredientScientificProperty`), scientific classification
  (`IngredientClassification`), health/dietary attributes
  (`IngredientHealthAttribute`), and a shared citation registry
  (`IngredientEnrichmentSource`).

  Every fact carries inline provenance (`source`, `confidence`, `reviewed`) plus
  an optional `enrichment_source_id`, mirroring the `IngredientTaxonomyNode`
  convention. These tables are keyed by `ingredient_id` and are never read or
  written by `FoodData.Usda.FoodParser` or `IngredientReconciliationWorker`, so
  enrichment survives every re-import and reconciliation pass.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    IngredientEnrichmentSource,
    IngredientScientificProperty,
    IngredientClassification,
    IngredientHealthAttribute
  }

  # ── Citation registry ──────────────────────────────────────────────────

  def create_enrichment_source(attrs) do
    %IngredientEnrichmentSource{}
    |> IngredientEnrichmentSource.changeset(attrs)
    |> Repo.insert()
  end

  def get_enrichment_source!(id), do: Repo.get!(IngredientEnrichmentSource, id)

  def list_enrichment_sources, do: Repo.all(IngredientEnrichmentSource)

  @doc """
  Find-or-create a citation by its natural key `(source_type, identifier)`,
  backed by the unique index.
  """
  def upsert_enrichment_source(attrs) do
    attrs
    |> create_enrichment_source()
    |> case do
      {:ok, source} ->
        {:ok, source}

      {:error, _changeset} ->
        source_type = attrs[:source_type] || attrs["source_type"]
        identifier = attrs[:identifier] || attrs["identifier"]

        {:ok,
         Repo.one!(
           from(s in IngredientEnrichmentSource,
             where: s.source_type == ^source_type and s.identifier == ^identifier
           )
         )}
    end
  end

  # ── Scientific properties (bioactive / compound measures) ───────────────

  def create_scientific_property(attrs) do
    %IngredientScientificProperty{}
    |> IngredientScientificProperty.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Insert or update a property, keyed on `(ingredient_id, property_key, source)`."
  def upsert_scientific_property(attrs) do
    %IngredientScientificProperty{}
    |> IngredientScientificProperty.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:ingredient_id, :property_key, :source]
    )
  end

  def list_scientific_properties(ingredient_id) do
    Repo.all(
      from(p in IngredientScientificProperty,
        where: p.ingredient_id == ^ingredient_id,
        order_by: [asc: p.property_key]
      )
    )
  end

  def delete_scientific_property(%IngredientScientificProperty{} = property),
    do: Repo.delete(property)

  # ── Scientific classification ───────────────────────────────────────────

  def create_classification(attrs) do
    %IngredientClassification{}
    |> IngredientClassification.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Insert or update a classification, keyed on `(ingredient_id, scientific_name)`."
  def upsert_classification(attrs) do
    %IngredientClassification{}
    |> IngredientClassification.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:ingredient_id, :scientific_name]
    )
  end

  def list_classifications(ingredient_id) do
    Repo.all(
      from(c in IngredientClassification,
        where: c.ingredient_id == ^ingredient_id,
        order_by: [asc: c.scientific_name]
      )
    )
  end

  def delete_classification(%IngredientClassification{} = classification),
    do: Repo.delete(classification)

  # ── Health / dietary attributes ─────────────────────────────────────────

  def create_health_attribute(attrs) do
    %IngredientHealthAttribute{}
    |> IngredientHealthAttribute.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Insert or update an attribute, keyed on `(ingredient_id, attribute, source)`."
  def upsert_health_attribute(attrs) do
    %IngredientHealthAttribute{}
    |> IngredientHealthAttribute.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:ingredient_id, :attribute, :source]
    )
  end

  def list_health_attributes(ingredient_id) do
    Repo.all(
      from(a in IngredientHealthAttribute,
        where: a.ingredient_id == ^ingredient_id,
        order_by: [asc: a.attribute]
      )
    )
  end

  def delete_health_attribute(%IngredientHealthAttribute{} = attribute),
    do: Repo.delete(attribute)

  # ── Aggregate read ──────────────────────────────────────────────────────

  @doc """
  All enrichment for an ingredient as
  `%{scientific_properties: [...], classifications: [...], health_attributes: [...]}`.
  """
  def list_enrichment(ingredient_id) do
    %{
      scientific_properties: list_scientific_properties(ingredient_id),
      classifications: list_classifications(ingredient_id),
      health_attributes: list_health_attributes(ingredient_id)
    }
  end
end
