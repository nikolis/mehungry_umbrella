defmodule Mehungry.Food.ParserVocabularyTest do
  use Mehungry.DataCase

  alias Mehungry.Food.{ParserVocabulary, ParserVocabularySeeder}
  alias Mehungry.Food.{CanonicalFood, ParserDescriptorAlias}
  alias Mehungry.FoodData.Usda.Parser.Vocabulary
  alias Mehungry.Repo

  setup do
    ParserVocabularySeeder.seed()
    :ok
  end

  test "seeding is idempotent" do
    foods_before = Repo.aggregate(CanonicalFood, :count)
    descriptors_before = Repo.aggregate(ParserDescriptorAlias, :count)

    ParserVocabularySeeder.seed()

    assert Repo.aggregate(CanonicalFood, :count) == foods_before
    assert Repo.aggregate(ParserDescriptorAlias, :count) == descriptors_before
  end

  test "dump/0 round-trips through Vocabulary.build/2" do
    vocab = Vocabulary.build(ParserVocabulary.dump())

    assert %{type: :food, value: "carrot"} = Vocabulary.lookup(vocab, "carrot")
    assert %{type: :food, value: "acerola"} = Vocabulary.lookup(vocab, "acerola cherry")

    assert %{type: :processing, value: "pickled", meta: meta} = Vocabulary.lookup(vocab, "pickle")
    assert meta.head == true
    assert meta.implied_food == "cucumber"
    assert is_integer(meta.implied_food_id)

    assert %{type: :harvest_stage, value: "baby"} = Vocabulary.lookup(vocab, "young")
    assert %{type: :part, value: "loin"} = Vocabulary.lookup(vocab, "loin")

    assert %{type: :dismemberment, value: "t bone steak"} =
             Vocabulary.lookup(vocab, "t bone steak")

    assert %{type: :bone_state, value: "boneless"} = Vocabulary.lookup(vocab, "boneless")
    assert %{type: :portion, value: "meat only"} = Vocabulary.lookup(vocab, "meat only")
    assert %{type: :grade, value: "choice"} = Vocabulary.lookup(vocab, "choice")
    assert %{type: :prepared, value: "commercial"} = Vocabulary.lookup(vocab, "commercial")
    assert %{type: :packaging, value: "canned"} = Vocabulary.lookup(vocab, "jarred")
    assert %{type: :not_food} = Vocabulary.lookup(vocab, "alcoholic beverage")
    assert %{type: :noise} = Vocabulary.lookup(vocab, "nfs")
    assert vocab.max_alias_words >= 2
  end

  test "mutations reload the persistent_term cache" do
    before_version = Vocabulary.get().version

    {:ok, _} = ParserVocabulary.add_descriptor_alias(%{alias: "smoky", kind: "modifier"})

    vocab = Vocabulary.get()
    assert vocab.version >= before_version
    assert %{type: :modifier, value: "smoky"} = Vocabulary.lookup(vocab, "smoky")
  end

  test "aliases are stored normalized" do
    {:ok, food} = ParserVocabulary.create_canonical_food(%{name: "Brussels Sprouts"})
    assert food.name == "brussels sprout"

    {:ok, found} = ParserVocabulary.get_or_create_canonical_food("Brussels sprouts")
    assert found.id == food.id
  end
end
