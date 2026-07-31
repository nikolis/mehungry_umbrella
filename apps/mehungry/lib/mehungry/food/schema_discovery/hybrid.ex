# apps/mehungry/lib/mehungry/food/schema_discovery/hybrid.ex
defmodule Mehungry.Food.SchemaDiscovery.Hybrid do
  @moduledoc """
  Hybrid schema discovery combining pure Elixir + semantic ML.
  Uses ML only where pure Elixir can't solve.
  """

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.IngredientParsedFood
  alias Mehungry.Repo

  # Ubiquitous modifiers/connectives stripped from names before embedding so the
  # clustering keys on the actual food, not on words like "raw" that every USDA
  # description shares. Also filtered out of the "common patterns" label.
  @stopwords MapSet.new(
               ~w(with and cooked raw or added fat from without prepared of on dry moisture solid breakfast pre-cooked unprepared unenriched grain whole mature vitamin canned sodium boneless)
             )

  # Single-link cosine cutoff used when a caller doesn't pass one. The admin page
  # overrides it live (see `group_embeddings/3`).
  @default_threshold 0.8

  @doc "The cosine cutoff applied when no threshold is supplied."
  def default_threshold, do: @default_threshold

  @doc """
  Enhanced schema discovery with semantic grouping.
  """
  @spec discover(float()) :: %{
          structural: map(),
          semantic_groups: [map()],
          recommendations: [map()],
          outliers: [map()]
        }
  def discover(threshold \\ @default_threshold) do
    structural = Mehungry.Food.SchemaDiscovery.PureEx.analyze()
    {ingredients, embeddings} = unmatched_embeddings()
    semantic_groups = group_embeddings(ingredients, embeddings, threshold)

    enhanced_recommendations =
      enhance_recommendations(structural.recommendations, semantic_groups)

    %{
      structural: structural,
      semantic_groups: semantic_groups,
      recommendations: enhanced_recommendations,
      outliers: ingredients
    }
  end

  @doc """
  The **expensive** step: find low-confidence ingredients and embed their
  (stopword-stripped) names once. Returns `{ingredients, embeddings}` aligned by
  index, or `{[], []}` when embeddings are off or there's too little to cluster.
  Cache the result and re-cluster with `group_embeddings/3` when only the
  threshold changes — no need to re-embed.
  """
  @spec unmatched_embeddings() :: {[map()], [[float()]]}
  def unmatched_embeddings do
    with true <- embeddings_enabled?(),
         ingredients when length(ingredients) > 5 <- find_unmatched_ingredients(),
         names = Enum.map(ingredients, &strip_stopwords(&1.name)),
         {:ok, embeddings} <- Mehungry.Food.Parser.Embedder.embed_all(names) do
      {ingredients, embeddings}
    else
      _ -> {[], []}
    end
  end

  @doc """
  The **cheap** step: cluster pre-computed `embeddings` at `threshold` and build
  the display groups. Safe to call repeatedly as the live knob moves.
  """
  @spec group_embeddings([map()], [[float()]], float()) :: [map()]
  def group_embeddings(ingredients, embeddings, threshold \\ @default_threshold)

  def group_embeddings([], _embeddings, _threshold), do: []

  def group_embeddings(ingredients, embeddings, threshold) do
    assignments = cluster_embeddings(embeddings, threshold)

    Enum.zip(ingredients, assignments)
    |> Enum.group_by(fn {_ing, cluster} -> cluster end)
    |> Enum.map(fn {cluster, items} ->
      cluster_items = Enum.map(items, fn {ing, _} -> ing end)

      %{
        cluster_id: cluster,
        size: length(cluster_items),
        ingredients: cluster_items,
        label: representative_word(cluster_items),
        common_patterns: find_common_patterns(cluster_items),
        suggested_field: infer_field_from_cluster(cluster_items)
      }
    end)
    |> Enum.sort_by(& &1.size, :desc)
  end

  defp find_unmatched_ingredients do
    # Find ingredients with low confidence or no canonical food
    parsed_foods =
      Repo.all(
        from p in IngredientParsedFood,
          where: p.confidence < 0.5 or is_nil(p.canonical_food_id),
          select: [:ingredient_id, :canonical_food_text]
      )

    ingredient_ids = Enum.map(parsed_foods, & &1.ingredient_id)

    Repo.all(
      from i in Ingredient,
        where: i.id in ^ingredient_ids,
        select: [:id, :name]
    )
  end

  # Single-link clustering at `threshold`. Returns **one cluster id per input
  # embedding, in input order** so `group_embeddings/3` can zip each ingredient
  # to its cluster. (A previous version returned one id per *cluster*, which made
  # the zip positional garbage and produced all-singleton groups.)
  @doc false
  def cluster_embeddings(embeddings, threshold \\ @default_threshold) do
    {_clusters, assignments} =
      Enum.reduce(embeddings, {[], []}, fn emb, {clusters, assigned} ->
        case find_cluster(emb, clusters, threshold) do
          {:ok, id} ->
            {update_cluster(clusters, id, emb), [id | assigned]}

          :not_found ->
            id = length(clusters)
            {[%{id: id, embeddings: [emb]} | clusters], [id | assigned]}
        end
      end)

    Enum.reverse(assignments)
  end

  defp find_cluster(emb, clusters, threshold) do
    Enum.find_value(clusters, :not_found, fn cluster ->
      if Enum.any?(cluster.embeddings, fn e -> cosine_similarity(emb, e) > threshold end) do
        {:ok, cluster.id}
      end
    end)
  end

  defp cosine_similarity(a, b) do
    dot =
      Enum.zip(a, b)
      |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)

    norm_a = Enum.reduce(a, 0.0, fn x, acc -> acc + x * x end) |> :math.sqrt()
    norm_b = Enum.reduce(b, 0.0, fn x, acc -> acc + x * x end) |> :math.sqrt()

    if norm_a == 0 or norm_b == 0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end

  defp update_cluster(clusters, id, emb) do
    Enum.map(clusters, fn
      %{id: ^id, embeddings: embs} -> %{id: id, embeddings: [emb | embs]}
      cluster -> cluster
    end)
  end

  defp find_common_patterns(ingredients) do
    names = Enum.map(ingredients, & &1.name)

    # Words shared by more than half the cluster, excluding stopwords so the
    # label reflects the food rather than ubiquitous modifiers like "raw".
    names
    |> Enum.flat_map(&tokenize/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_word, count} -> count > length(names) / 2 end)
    |> Enum.map(fn {word, _count} -> word end)
  end

  # Split a name into meaningful, lowercased tokens: drops stopwords, blanks, and
  # single characters (e.g. the "a"/"d" left over from "vitamin A / vitamin D").
  defp tokenize(name) do
    name
    |> String.downcase()
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.reject(&(MapSet.member?(@stopwords, &1) or String.length(&1) < 2))
  end

  # Exactly one label word per cluster. Ranked by, in order: how many names it
  # appears in (frequency), how early it tends to appear (USDA puts the head food
  # first, e.g. "Milk, whole, …"), then the shorter word ("milk" over "milkfat").
  # `nil` only when every name reduced to nothing.
  defp representative_word(ingredients) do
    token_lists = Enum.map(ingredients, fn ing -> ing.name |> tokenize() |> Enum.uniq() end)

    token_lists
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(fn word -> {word, word_score(word, token_lists)} end)
    |> Enum.max_by(fn {_word, score} -> score end, fn -> {nil, nil} end)
    |> elem(0)
  end

  # {count, -avg_position, -length} — larger is better on each, in that priority.
  defp word_score(word, token_lists) do
    positions =
      token_lists
      |> Enum.map(&Enum.find_index(&1, fn t -> t == word end))
      |> Enum.reject(&is_nil/1)

    count = length(positions)
    avg_position = Enum.sum(positions) / count

    {count, -avg_position, -String.length(word)}
  end

  @doc false
  def strip_stopwords(name) do
    case tokenize(name) do
      # Never embed an empty string; fall back to the original name.
      [] -> name
      tokens -> Enum.join(tokens, " ")
    end
  end

  defp infer_field_from_cluster(ingredients) do
    # Look at common patterns to suggest a field name
    patterns = find_common_patterns(ingredients)

    case patterns do
      ["trimmed", "to" | _] -> :trimmed_to
      ["grade" | _] -> :grade
      ["boneless" | _] -> :cut_type
      ["raw" | _] -> :preparation
      ["baby" | _] -> :maturity
      _ -> :unknown_field
    end
  end

  defp enhance_recommendations(structural_recs, semantic_groups) do
    # Add semantic findings to structural recommendations
    semantic_fields = Enum.map(semantic_groups, & &1.suggested_field)

    # Update structural recommendations with semantic insights
    Enum.map(structural_recs, fn rec ->
      if rec.field in semantic_fields do
        Map.put(rec, :semantic_evidence, true)
      else
        rec
      end
    end)
  end

  defp embeddings_enabled? do
    Application.get_env(:mehungry, :enable_embeddings, false)
  end
end
