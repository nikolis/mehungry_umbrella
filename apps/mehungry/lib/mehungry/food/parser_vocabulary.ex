defmodule Mehungry.Food.ParserVocabulary do
  @moduledoc """
  DB persistence for the USDA description parser's vocabulary — the canonical
  food lexicon, processing methods, harvest stages, meat parts/dismemberments,
  packaging and descriptor aliases the classifier consults.

  `dump/0` produces the input `Parser.Vocabulary.build/2` expects; every
  mutating function ends with `Parser.Vocabulary.reload/0` so the
  `:persistent_term` cache never serves stale aliases (writes happen at
  admin-edit/seed frequency only). All alias changesets normalize through
  `Parser.Normalizer`, keeping lookups normalized-vs-normalized.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    CanonicalFood,
    CanonicalFoodAlias,
    ParserDescriptorAlias,
    ParserDismemberment,
    ParserDismembermentAlias,
    ParserHarvestStage,
    ParserHarvestStageAlias,
    ParserPackagingAlias,
    ParserPart,
    ParserPartAlias,
    ParserProcessingAlias,
    ParserProcessingMethod
  }

  alias Mehungry.FoodData.Usda.Parser.Normalizer
  alias Mehungry.FoodData.Usda.Parser.Vocabulary

  @doc "All vocabulary rows in the shape `Parser.Vocabulary.build/2` consumes."
  def dump do
    [
      foods: dump_foods(),
      processing: dump_processing(),
      harvest_stages: dump_harvest_stages(),
      parts: dump_parts(),
      dismemberments: dump_dismemberments(),
      packaging: dump_packaging(),
      descriptors: dump_descriptors()
    ]
  end

  # ── Canonical foods ───────────────────────────────────────────────────────

  def create_canonical_food(attrs) do
    %CanonicalFood{}
    |> CanonicalFood.changeset(Map.new(attrs))
    |> Repo.insert()
    |> reload_on_ok()
  end

  @doc """
  Find-or-create by normalized name. Does **not** reload the vocabulary cache
  by itself — `ParsedFoods.verify_parsed_food/2` calls it inside a transaction
  and reloads after commit.
  """
  def get_or_create_canonical_food(name) do
    normalized = Normalizer.normalize(name)

    case Repo.get_by(CanonicalFood, name: normalized) do
      %CanonicalFood{} = food ->
        {:ok, food}

      nil ->
        case %CanonicalFood{} |> CanonicalFood.changeset(%{name: name}) |> Repo.insert() do
          {:ok, food} -> {:ok, food}
          # Lost an insert race on the unique index — fetch the winner.
          {:error, _changeset} -> {:ok, Repo.get_by!(CanonicalFood, name: normalized)}
        end
    end
  end

  def add_food_alias(canonical_food_id, alias_text) do
    %CanonicalFoodAlias{}
    |> CanonicalFoodAlias.changeset(%{canonical_food_id: canonical_food_id, alias: alias_text})
    |> Repo.insert()
    |> reload_on_ok()
  end

  # ── Processing methods ────────────────────────────────────────────────────

  def add_processing_method(name) do
    %ParserProcessingMethod{}
    |> ParserProcessingMethod.changeset(%{name: name})
    |> Repo.insert()
    |> reload_on_ok()
  end

  def add_processing_alias(processing_method_id, attrs) do
    %ParserProcessingAlias{}
    |> ParserProcessingAlias.changeset(
      attrs
      |> Map.new()
      |> Map.put(:processing_method_id, processing_method_id)
    )
    |> Repo.insert()
    |> reload_on_ok()
  end

  # ── Harvest stages ────────────────────────────────────────────────────────

  def add_harvest_stage(name) do
    %ParserHarvestStage{}
    |> ParserHarvestStage.changeset(%{name: name})
    |> Repo.insert()
    |> reload_on_ok()
  end

  def add_harvest_stage_alias(harvest_stage_id, alias_text) do
    %ParserHarvestStageAlias{}
    |> ParserHarvestStageAlias.changeset(%{harvest_stage_id: harvest_stage_id, alias: alias_text})
    |> Repo.insert()
    |> reload_on_ok()
  end

  # ── Parts + dismemberments ────────────────────────────────────────────────

  def add_part(name) do
    %ParserPart{}
    |> ParserPart.changeset(%{name: name})
    |> Repo.insert()
    |> reload_on_ok()
  end

  def add_part_alias(part_id, alias_text) do
    %ParserPartAlias{}
    |> ParserPartAlias.changeset(%{part_id: part_id, alias: alias_text})
    |> Repo.insert()
    |> reload_on_ok()
  end

  def add_dismemberment(name) do
    %ParserDismemberment{}
    |> ParserDismemberment.changeset(%{name: name})
    |> Repo.insert()
    |> reload_on_ok()
  end

  def add_dismemberment_alias(dismemberment_id, alias_text) do
    %ParserDismembermentAlias{}
    |> ParserDismembermentAlias.changeset(%{
      dismemberment_id: dismemberment_id,
      alias: alias_text
    })
    |> Repo.insert()
    |> reload_on_ok()
  end

  # ── Packaging + descriptors ───────────────────────────────────────────────

  def add_packaging_alias(attrs) do
    %ParserPackagingAlias{}
    |> ParserPackagingAlias.changeset(Map.new(attrs))
    |> Repo.insert()
    |> reload_on_ok()
  end

  def add_descriptor_alias(attrs) do
    %ParserDescriptorAlias{}
    |> ParserDescriptorAlias.changeset(Map.new(attrs))
    |> Repo.insert()
    |> reload_on_ok()
  end

  # ── Dump internals ────────────────────────────────────────────────────────

  defp dump_foods do
    CanonicalFood
    |> Repo.all()
    |> Repo.preload(:aliases)
    |> Enum.map(fn food ->
      %{id: food.id, name: food.name, aliases: Enum.map(food.aliases, & &1.alias)}
    end)
  end

  defp dump_processing do
    food_names = Map.new(Repo.all(from(f in CanonicalFood, select: {f.id, f.name})))

    ParserProcessingMethod
    |> Repo.all()
    |> Repo.preload(:aliases)
    |> Enum.map(fn method ->
      %{
        name: method.name,
        aliases:
          Enum.map(method.aliases, fn a ->
            %{
              alias: a.alias,
              head: a.head_template,
              implied_food: food_names[a.implied_canonical_food_id],
              implied_food_id: a.implied_canonical_food_id
            }
          end)
      }
    end)
  end

  defp dump_harvest_stages do
    ParserHarvestStage
    |> Repo.all()
    |> Repo.preload(:aliases)
    |> Enum.map(fn stage ->
      %{name: stage.name, aliases: Enum.map(stage.aliases, & &1.alias)}
    end)
  end

  defp dump_parts do
    ParserPart
    |> Repo.all()
    |> Repo.preload(:aliases)
    |> Enum.map(fn part ->
      %{name: part.name, aliases: Enum.map(part.aliases, & &1.alias)}
    end)
  end

  defp dump_dismemberments do
    ParserDismemberment
    |> Repo.all()
    |> Repo.preload(:aliases)
    |> Enum.map(fn dismemberment ->
      %{name: dismemberment.name, aliases: Enum.map(dismemberment.aliases, & &1.alias)}
    end)
  end

  defp dump_packaging do
    Enum.map(Repo.all(ParserPackagingAlias), &%{alias: &1.alias, packaging: &1.packaging})
  end

  defp dump_descriptors do
    Enum.map(Repo.all(ParserDescriptorAlias), &%{alias: &1.alias, kind: &1.kind})
  end

  defp reload_on_ok({:ok, _} = result) do
    Vocabulary.reload()
    result
  end

  defp reload_on_ok(other), do: other
end
