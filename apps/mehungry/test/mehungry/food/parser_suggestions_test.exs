defmodule Mehungry.Food.ParserSuggestionsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.{CanonicalFoodAlias, IngredientParsedFood, ParserVocabulary}
  alias Mehungry.FoodData.Usda.Parser.Pipeline
  alias Mehungry.Repo

  # Builds a low-confidence, unresolved parse (head noun missed the vocabulary)
  # plus a semantic suggestion pointing it at an existing canonical food — the
  # exact rows the embedding-backed generator would produce, minus the model.
  defp unresolved_parse_with_suggestion(surface, canonical_name, score \\ 0.9) do
    {:ok, canonical} = ParserVocabulary.get_or_create_canonical_food(canonical_name)

    ingredient =
      ingredient_fixture(%{name: "#{surface} thing", fdc_id: System.unique_integer([:positive])})

    {:ok, parse} =
      %IngredientParsedFood{}
      |> IngredientParsedFood.changeset(%{
        ingredient_id: ingredient.id,
        canonical_food_text: surface,
        confidence: 0.5,
        parser_version: Pipeline.version(),
        status: "candidate"
      })
      |> Repo.insert()

    {:ok, suggestion} =
      %Mehungry.Food.ParserSuggestionCandidate{}
      |> Mehungry.Food.ParserSuggestionCandidate.changeset(%{
        ingredient_parsed_food_id: parse.id,
        surface_text: surface,
        suggested_target: canonical.name,
        suggested_canonical_food_id: canonical.id,
        score: score,
        status: "candidate",
        model_version: "test-model"
      })
      |> Repo.insert()

    %{canonical: canonical, parse: parse, suggestion: suggestion}
  end

  describe "generate_batch/2" do
    test "no-ops when embeddings are disabled (test env)" do
      assert {:error, :embeddings_disabled} = Food.generate_parser_suggestions(0, limit: 10)
    end
  end

  describe "accept/2" do
    test "records the surface→canonical alias and marks the suggestion accepted" do
      %{canonical: canonical, suggestion: suggestion} =
        unresolved_parse_with_suggestion("courgette", "zucchini")

      assert Repo.get_by(CanonicalFoodAlias, canonical_food_id: canonical.id, alias: "courgette") ==
               nil

      assert {:ok, accepted} = Food.accept_parser_suggestion(suggestion.id)
      assert accepted.status == "accepted"
      assert accepted.reviewed_at

      # The alias now exists, so the parser vocabulary can resolve "courgette".
      assert %CanonicalFoodAlias{} =
               Repo.get_by(CanonicalFoodAlias,
                 canonical_food_id: canonical.id,
                 alias: "courgette"
               )
    end

    test "is rejected when the suggestion has no canonical food target" do
      %{suggestion: suggestion} = unresolved_parse_with_suggestion("courgette", "zucchini")

      # Simulate the canonical food having been deleted (FK nilified).
      suggestion
      |> Ecto.Changeset.change(suggested_canonical_food_id: nil)
      |> Repo.update!()

      assert {:error, :canonical_food_missing} = Food.accept_parser_suggestion(suggestion.id)
    end

    test "twice-accepting is rejected (no longer pending)" do
      %{suggestion: suggestion} = unresolved_parse_with_suggestion("courgette", "zucchini")
      assert {:ok, _} = Food.accept_parser_suggestion(suggestion.id)
      assert {:error, :not_pending} = Food.accept_parser_suggestion(suggestion.id)
    end
  end

  describe "reject/2 and list_pending/1" do
    test "rejecting removes it from the pending list" do
      %{suggestion: suggestion} = unresolved_parse_with_suggestion("courgette", "zucchini")

      assert Enum.any?(Food.list_pending_parser_suggestions(), &(&1.id == suggestion.id))

      assert {:ok, rejected} = Food.reject_parser_suggestion(suggestion.id)
      assert rejected.status == "rejected"
      refute Enum.any?(Food.list_pending_parser_suggestions(), &(&1.id == suggestion.id))
    end
  end
end
