defmodule Mehungry.FoodData.Usda.Parser.Vocabulary do
  @moduledoc """
  The in-memory alias dictionary the classifier consults.

  Built from the DB vocabulary tables via `Mehungry.Food.ParserVocabulary.dump/0`
  and cached in `:persistent_term` — reads are zero-copy and happen on every
  parse; writes only happen on admin edits or seeding, when
  `Mehungry.Food.ParserVocabulary` calls `reload/0`.

  Tests build fixture vocabularies without a DB via `build/2`. Its input is a
  keyword list:

      build(
        foods: [%{name: "carrot", id: 1, aliases: ["carrot"]}],
        processing: [
          %{name: "raw", aliases: ["raw"]},
          %{name: "pickled",
            aliases: [%{alias: "pickle", head: true, implied_food: "cucumber", implied_food_id: 2}]}
        ],
        harvest_stages: [%{name: "baby", aliases: ["baby", "young"]}],
        parts: [%{name: "loin", aliases: ["loin"]}],
        dismemberments: [%{name: "t bone steak", aliases: ["t-bone steak", "t bone steak"]}],
        packaging: [%{alias: "canned", packaging: "canned"}],
        descriptors: [
          %{alias: "dill", kind: "modifier"},
          %{alias: "boneless", kind: "bone_state"},
          %{alias: "meat only", kind: "portion"},
          %{alias: "choice", kind: "grade"},
          %{alias: "commercial", kind: "prepared"}
        ]
      )

  Descriptor `kind` is one of `not_food | modifier | noise | bone_state |
  portion | grade | prepared` (see `Parser.Rules` for what each does).

  Aliases are normalized through `Parser.Normalizer.normalize/1` at build
  time, so lookups are guaranteed normalized-vs-normalized. When the same
  alias appears in several categories the first one wins, in this precedence
  order: not-food descriptors, processing, harvest stages, parts,
  dismemberments, packaging, foods, remaining descriptors (modifier/noise/
  bone_state/portion/grade/prepared).
  """

  alias Mehungry.FoodData.Usda.Parser.{Normalizer, Token}

  @persistent_key {__MODULE__, :current}

  @type entry :: %{type: Token.type() | :noise, value: String.t(), meta: map()}

  @type t :: %__MODULE__{
          aliases: %{String.t() => entry()},
          max_alias_words: pos_integer(),
          version: integer()
        }

  defstruct aliases: %{}, max_alias_words: 1, version: 0

  @doc "Returns the cached vocabulary, loading it from the DB on first use."
  @spec get() :: t()
  def get do
    :persistent_term.get(@persistent_key)
  rescue
    ArgumentError -> reload()
  end

  @doc "Rebuilds the vocabulary from the DB and replaces the cached copy."
  @spec reload() :: t()
  def reload do
    vocab = build(loader().(), version: System.system_time(:millisecond))
    :persistent_term.put(@persistent_key, vocab)
    vocab
  end

  @spec lookup(t(), String.t()) :: entry() | nil
  def lookup(%__MODULE__{aliases: aliases}, phrase), do: Map.get(aliases, phrase)

  @spec build(keyword(), keyword()) :: t()
  def build(data, opts \\ []) do
    descriptors = Keyword.get(data, :descriptors, [])
    {not_food, other_descriptors} = Enum.split_with(descriptors, &(&1.kind == "not_food"))

    aliases =
      [
        Enum.map(not_food, &{&1.alias, %{type: :not_food, value: &1.alias, meta: %{}}}),
        processing_entries(Keyword.get(data, :processing, [])),
        stage_entries(Keyword.get(data, :harvest_stages, [])),
        part_entries(Keyword.get(data, :parts, [])),
        dismemberment_entries(Keyword.get(data, :dismemberments, [])),
        packaging_entries(Keyword.get(data, :packaging, [])),
        food_entries(Keyword.get(data, :foods, [])),
        Enum.map(
          other_descriptors,
          &{&1.alias, %{type: descriptor_type(&1.kind), value: &1.alias, meta: %{}}}
        )
      ]
      |> Enum.reduce(%{}, fn pairs, acc ->
        Enum.reduce(pairs, acc, fn {alias_text, entry}, inner ->
          key = Normalizer.normalize(alias_text)
          Map.put_new(inner, key, %{entry | value: normalize_value(entry, key)})
        end)
      end)

    max_words =
      aliases
      |> Map.keys()
      |> Enum.map(&(&1 |> String.split(" ") |> length()))
      |> Enum.max(fn -> 1 end)

    %__MODULE__{
      aliases: aliases,
      max_alias_words: max_words,
      version: Keyword.get(opts, :version, 0)
    }
  end

  # Free-standing descriptor entries (not-food, modifier, noise, and the
  # bone_state/portion/grade/prepared kinds) carry the (normalized) alias itself
  # as value; every other category resolves the alias to its canonical name.
  @self_valued [:not_food, :modifier, :noise, :bone_state, :portion, :grade, :prepared]
  defp normalize_value(%{type: type}, key) when type in @self_valued, do: key
  defp normalize_value(%{value: value}, _key), do: value

  defp food_entries(foods) do
    Enum.flat_map(foods, fn food ->
      entry = %{type: :food, value: food.name, meta: %{food_id: Map.get(food, :id)}}
      for alias_text <- [food.name | Map.get(food, :aliases, [])], do: {alias_text, entry}
    end)
  end

  defp processing_entries(methods) do
    Enum.flat_map(methods, fn method ->
      for alias_spec <- Map.get(method, :aliases, [method.name]) do
        {alias_text, meta} = processing_alias(alias_spec)
        {alias_text, %{type: :processing, value: method.name, meta: meta}}
      end
    end)
  end

  defp processing_alias(alias_text) when is_binary(alias_text), do: {alias_text, %{}}

  defp processing_alias(%{alias: alias_text} = spec) do
    meta =
      spec
      |> Map.take([:head, :implied_food, :implied_food_id])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == false end)
      |> Map.new()

    {alias_text, meta}
  end

  defp stage_entries(stages) do
    Enum.flat_map(stages, fn stage ->
      entry = %{type: :harvest_stage, value: stage.name, meta: %{}}
      for alias_text <- [stage.name | Map.get(stage, :aliases, [])], do: {alias_text, entry}
    end)
  end

  defp part_entries(parts) do
    Enum.flat_map(parts, fn part ->
      entry = %{type: :part, value: part.name, meta: %{}}
      for alias_text <- [part.name | Map.get(part, :aliases, [])], do: {alias_text, entry}
    end)
  end

  defp dismemberment_entries(dismemberments) do
    Enum.flat_map(dismemberments, fn dismemberment ->
      entry = %{type: :dismemberment, value: dismemberment.name, meta: %{}}

      for alias_text <- [dismemberment.name | Map.get(dismemberment, :aliases, [])],
          do: {alias_text, entry}
    end)
  end

  defp packaging_entries(packaging) do
    Enum.map(packaging, fn pkg ->
      {pkg.alias, %{type: :packaging, value: pkg.packaging, meta: %{}}}
    end)
  end

  defp descriptor_type("modifier"), do: :modifier
  defp descriptor_type("noise"), do: :noise
  defp descriptor_type("bone_state"), do: :bone_state
  defp descriptor_type("portion"), do: :portion
  defp descriptor_type("grade"), do: :grade
  defp descriptor_type("prepared"), do: :prepared

  defp loader do
    Application.get_env(
      :mehungry,
      :usda_parser_vocabulary_loader,
      &Mehungry.Food.ParserVocabulary.dump/0
    )
  end
end
