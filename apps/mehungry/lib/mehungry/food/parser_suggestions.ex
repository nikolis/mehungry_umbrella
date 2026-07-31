defmodule Mehungry.Food.ParserSuggestions do
  @moduledoc """
  Review-gated semantic suggestions over the deterministic parser's own
  low-confidence output.

  The deterministic parser resolves a description against a hand-seeded alias
  vocabulary; when the head noun misses, it stores the raw phrase as free-text
  (`canonical_food_id: nil`) at low confidence. This module embeds those
  unresolved surface strings (`Mehungry.AI.SemanticMatcher`) and proposes the
  nearest existing `CanonicalFood` as a `ParserSuggestionCandidate` for admin
  review. Accepting one adds a `CanonicalFoodAlias` through the existing
  `ParserVocabulary.add_food_alias/2` path, so the next parse of that ingredient
  resolves — the lexicon grows from ranked suggestions instead of pure hand
  authoring. Nothing here writes facts or is consulted by the parser at runtime.

  Requires `:enable_embeddings` + a populated `canonical_foods.embedding`
  (`CanonicalFoodEmbeddingWorker`); when embeddings are off, generation is a
  no-op and the deterministic pipeline is unaffected.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    IngredientParsedFood,
    ParserSuggestionCandidate,
    ParserVocabulary
  }

  alias Mehungry.AI.SemanticMatcher
  alias Mehungry.FoodData.Usda.Parser.Pipeline

  # Parses at/below this confidence are candidates for a semantic suggestion.
  @low_confidence 0.6
  # How many nearest canonical foods to record per unresolved parse.
  @suggestions_per_parse 3

  # ── Generation ─────────────────────────────────────────────────────────────

  @doc """
  Generate suggestions for one id-ordered batch of unresolved, low-confidence
  parses with `id > after_id`. Returns
  `{:ok, %{inserted: n, batch: count, last_id: id | nil}}` (drive the cursor with
  `last_id`) or `{:error, reason}` (e.g. `:embeddings_disabled`). Cursor-based so
  it always terminates even when a parse has no match above the threshold;
  idempotent via the unique `(parse, target, kind)` index.
  """
  def generate_batch(after_id \\ 0, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    threshold = Keyword.get(opts, :threshold, SemanticMatcher.similarity_threshold())

    if SemanticMatcher.available?() do
      parses = unresolved_parses(after_id, limit)
      inserted = Enum.reduce(parses, 0, fn p, acc -> acc + generate_for_parse(p, threshold) end)
      last_id = if parses == [], do: nil, else: List.last(parses).id

      {:ok, %{inserted: inserted, batch: length(parses), last_id: last_id}}
    else
      {:error, :embeddings_disabled}
    end
  end

  @doc """
  Generate (and persist) suggestions for one parse. Returns the number of
  candidate rows inserted (0 when the semantic search finds nothing above the
  threshold). Safe to call repeatedly.
  """
  def generate_for_parse(%IngredientParsedFood{} = parse, threshold \\ nil) do
    threshold = threshold || SemanticMatcher.similarity_threshold()
    surface = parse.canonical_food_text

    with true <- is_binary(surface) and surface != "",
         {:ok, matches} <-
           SemanticMatcher.search(surface, limit: @suggestions_per_parse, threshold: threshold) do
      matches
      |> Enum.map(&candidate_attrs(parse, surface, &1))
      |> Enum.map(&insert_candidate/1)
      |> Enum.count(&match?({:ok, _}, &1))
    else
      _ -> 0
    end
  end

  defp candidate_attrs(parse, surface, %{id: cf_id, name: name, similarity: score}) do
    %{
      ingredient_parsed_food_id: parse.id,
      suggestion_kind: "canonical_food",
      surface_text: surface,
      suggested_target: name,
      suggested_canonical_food_id: cf_id,
      score: score,
      status: "candidate",
      model_version: SemanticMatcher.model_name()
    }
  end

  defp insert_candidate(attrs) do
    %ParserSuggestionCandidate{}
    |> ParserSuggestionCandidate.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target:
        {:unsafe_fragment, "(ingredient_parsed_food_id, suggested_target, suggestion_kind)"}
    )
  end

  # Low-confidence, non-skipped, unresolved (no lexicon link) parses at the
  # current parser version, id-ordered above the cursor. Re-processing an
  # already-suggested parse is harmless (idempotent insert), so no anti-join is
  # needed and the id cursor guarantees the batch worker terminates.
  defp unresolved_parses(after_id, limit) do
    Repo.all(
      from(p in IngredientParsedFood,
        where:
          p.parser_version == ^Pipeline.version() and is_nil(p.skip_reason) and
            is_nil(p.canonical_food_id) and not is_nil(p.canonical_food_text) and
            p.confidence <= @low_confidence and p.id > ^after_id,
        order_by: [asc: p.id],
        limit: ^limit
      )
    )
  end

  # ── Review ─────────────────────────────────────────────────────────────────

  @doc "Pending suggestions, highest score first, parse + ingredient preloaded."
  def list_pending(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(s in ParserSuggestionCandidate,
        where: s.status == "candidate",
        order_by: [desc: s.score, asc: s.id],
        preload: [ingredient_parsed_food: :ingredient],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  @doc """
  Accept a suggestion: record the alias `surface_text → suggested canonical food`
  through the existing vocabulary path (which reloads the parser cache), and mark
  the row `accepted`. The ingredient can then be re-parsed to resolve.
  """
  def accept(id, user_id \\ nil) do
    suggestion = Repo.get!(ParserSuggestionCandidate, id)

    cond do
      suggestion.status != "candidate" ->
        {:error, :not_pending}

      is_nil(suggestion.suggested_canonical_food_id) ->
        {:error, :canonical_food_missing}

      true ->
        with {:ok, _alias} <-
               ParserVocabulary.add_food_alias(
                 suggestion.suggested_canonical_food_id,
                 suggestion.surface_text
               ) do
          mark(suggestion, "accepted", user_id)
        end
    end
  end

  @doc "Reject a suggestion (kept for history)."
  def reject(id, user_id \\ nil) do
    Repo.get!(ParserSuggestionCandidate, id) |> mark("rejected", user_id)
  end

  defp mark(suggestion, status, user_id) do
    suggestion
    |> ParserSuggestionCandidate.changeset(%{
      status: status,
      reviewed_by_user_id: user_id,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end
end
