defmodule Mehungry.Food.ParserVocabularySeeder do
  @moduledoc """
  Idempotent seed set for the USDA description parser vocabulary — enough to
  parse the golden examples in `docs/usda_description_parser.md`. Safe to run
  repeatedly (`on_conflict: :nothing` against the unique alias indexes);
  reloads the in-memory `Parser.Vocabulary` once at the end.
  """

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

  alias Mehungry.FoodData.Usda.Parser.Vocabulary

  @foods %{
    "carrot" => [],
    "cucumber" => [],
    "corn" => [],
    "tomato" => [],
    "acerola" => ["acerola cherry"],
    "spinach" => [],
    "chestnut" => [],
    "beef" => []
  }

  # method => aliases; maps mark head-template aliases and implied foods
  @processing %{
    "raw" => ["raw"],
    "pickled" => [%{alias: "pickle", head_template: true, implied_food: "cucumber"}, "pickled"],
    "oil" => [%{alias: "oil", head_template: true}],
    "puree" => ["puree", "pureed"],
    "juice" => ["juice"],
    "frozen" => ["frozen"],
    "dried" => ["dried", "dehydrated"],
    "roasted" => ["roasted", "dry roasted"],
    "boiled" => ["boiled"]
  }

  @harvest_stages %{
    "baby" => ["baby", "young", "immature"],
    "mature" => ["mature"]
  }

  @parts %{
    "loin" => ["loin"],
    "chuck" => ["chuck"],
    "rib" => ["rib"]
  }

  @dismemberments %{
    "t bone steak" => ["t-bone steak", "t bone steak"],
    "porterhouse steak" => ["porterhouse steak"],
    "top loin steak" => ["top loin steak"],
    "rib eye steak" => ["rib eye steak"],
    "tenderloin" => ["tenderloin"]
  }

  @packaging %{"canned" => "canned", "jarred" => "canned"}

  @descriptors %{
    "not_food" => ["alcoholic beverage", "alcohol"],
    "modifier" => [
      "dill",
      "kosher dill",
      "chopped",
      "leaf",
      "seed",
      "fruit",
      "european",
      "table",
      "red",
      "sweetened",
      "unsweetened"
    ],
    "noise" => ["nfs", "all varieties", "includes usda commodity"],
    "bone_state" => ["boneless", "bone-in", "bone in", "lip-on", "lip on"],
    "portion" => [
      "meat only",
      "meat and skin",
      "skin on",
      "skinless",
      "flesh and skin",
      "with skin",
      "without skin",
      "skin",
      "peel",
      "with peel",
      "without peel",
      "unpeeled",
      "separable lean",
      "separable lean only",
      "separable lean and fat"
    ],
    "grade" => ["choice", "select", "prime", "standard", "grade a"],
    "prepared" => [
      "commercial",
      "commercially baked",
      "homemade",
      "fast food",
      "restaurant prepared",
      "restaurant style"
    ]
  }

  def seed do
    foods = seed_foods()
    seed_processing(foods)
    seed_harvest_stages()
    seed_parts()
    seed_dismemberments()
    seed_packaging()
    seed_descriptors()
    Vocabulary.reload()
    :ok
  end

  defp seed_foods do
    Map.new(@foods, fn {name, aliases} ->
      food = upsert(CanonicalFood, %{name: name}, [:name], name: name)

      for alias_text <- aliases do
        upsert(CanonicalFoodAlias, %{canonical_food_id: food.id, alias: alias_text}, [:alias],
          alias: alias_text
        )
      end

      {name, food}
    end)
  end

  defp seed_processing(foods) do
    for {name, aliases} <- @processing do
      method = upsert(ParserProcessingMethod, %{name: name}, [:name], name: name)
      Enum.each(aliases, &seed_processing_alias(&1, method, foods))
    end
  end

  defp seed_processing_alias(alias_spec, method, foods) do
    attrs = processing_alias_attrs(alias_spec, foods)

    upsert(
      ParserProcessingAlias,
      Map.put(attrs, :processing_method_id, method.id),
      [:alias],
      alias: attrs.alias
    )
  end

  defp processing_alias_attrs(alias_text, _foods) when is_binary(alias_text),
    do: %{alias: alias_text}

  defp processing_alias_attrs(%{} = spec, foods) do
    spec
    |> Map.delete(:implied_food)
    |> Map.put(:implied_canonical_food_id, implied_food_id(foods, spec))
  end

  defp implied_food_id(foods, %{implied_food: name}),
    do: foods |> Map.fetch!(name) |> Map.fetch!(:id)

  defp implied_food_id(_foods, _spec), do: nil

  defp seed_harvest_stages do
    for {name, aliases} <- @harvest_stages do
      stage = upsert(ParserHarvestStage, %{name: name}, [:name], name: name)

      for alias_text <- aliases do
        upsert(
          ParserHarvestStageAlias,
          %{harvest_stage_id: stage.id, alias: alias_text},
          [:alias],
          alias: alias_text
        )
      end
    end
  end

  defp seed_parts do
    for {name, aliases} <- @parts do
      part = upsert(ParserPart, %{name: name}, [:name], name: name)

      for alias_text <- aliases do
        upsert(ParserPartAlias, %{part_id: part.id, alias: alias_text}, [:alias],
          alias: alias_text
        )
      end
    end
  end

  defp seed_dismemberments do
    for {name, aliases} <- @dismemberments do
      dismemberment = upsert(ParserDismemberment, %{name: name}, [:name], name: name)

      for alias_text <- aliases do
        upsert(
          ParserDismembermentAlias,
          %{dismemberment_id: dismemberment.id, alias: alias_text},
          [:alias],
          alias: alias_text
        )
      end
    end
  end

  defp seed_packaging do
    for {alias_text, packaging} <- @packaging do
      upsert(ParserPackagingAlias, %{alias: alias_text, packaging: packaging}, [:alias],
        alias: alias_text
      )
    end
  end

  defp seed_descriptors do
    for {kind, aliases} <- @descriptors, alias_text <- aliases do
      upsert(ParserDescriptorAlias, %{alias: alias_text, kind: kind}, [:alias], alias: alias_text)
    end
  end

  # Insert-or-fetch through the schema changeset (aliases get normalized, so
  # the fetch-back key is read from the changeset, not the raw attrs).
  defp upsert(schema, attrs, conflict_target, get_by) do
    changeset = schema.changeset(struct(schema), attrs)

    Repo.insert(changeset, on_conflict: :nothing, conflict_target: conflict_target)

    get_by =
      Enum.map(get_by, fn {key, _raw} -> {key, Ecto.Changeset.get_field(changeset, key)} end)

    Repo.get_by!(schema, get_by)
  end
end
