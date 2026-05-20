# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  @moduledoc """
  Simple ingredient search that prioritizes exact matches
  """

  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient
def search_robust_with_position(search_term, classes \\ []) do
  cleaned_term = String.trim(search_term)
  
  # Normalize search term
  search_words = String.split(cleaned_term, " ")
  search_phrase = Enum.join(search_words, " ")
  
  # Build query that matches each word anywhere
  conditions = Enum.map(search_words, fn word ->
    dynamic([i], ilike(i.name, ^"%#{word}%"))
  end)
  
  combined_condition = Enum.reduce(conditions, fn cond, acc ->
    dynamic([i], ^cond and ^acc)
  end)
  
  candidates_query = from i in Ingredient,
    where: not is_nil(i.name),
    where: i.category_id not in ^get_second_layer_foods_ids(),
    where: ^combined_condition,
    limit: 200
  
  candidates = 
    candidates_query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  
  # Rank with position awareness
  candidates
  |> Enum.map(fn i ->
    # Normalize name (remove punctuation, lowercase)
    name_normalized = i.name
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    
    # Calculate scores
    position_score = calculate_position_score(name_normalized, search_words)
    order_score = calculate_word_order_score(name_normalized, search_words)
    phrase_score = calculate_phrase_score(name_normalized, search_phrase)
    
    # Bonus for shorter names
    length_bonus = if String.length(i.name) < 30, do: 30, else: 0
    
    total_score = position_score + order_score + phrase_score + length_bonus
    
    {i, total_score}
  end)
  |> Enum.sort_by(fn {_i, score} -> -score end)
  |> Enum.map(fn {i, _score} -> i end)
  |> Enum.take(20)
end

defp calculate_position_score(name_normalized, search_words) do
  name_parts = String.split(name_normalized, " ")
  
  # Find position of first matching word
  first_match_index = Enum.find_index(name_parts, fn word ->
    Enum.any?(search_words, &String.contains?(word, &1))
  end)
  
  case first_match_index do
    nil -> 0
    0 -> 500      # First word matches - best
    1 -> 300      # Second word matches
    2 -> 200      # Third word matches
    3 -> 100      # Fourth word matches
    _ -> 50       # Later matches
  end
end

defp calculate_word_order_score(name_normalized, search_words) do
  name_parts = String.split(name_normalized, " ")
  
  # Check if search words appear in order (as subsequence)
  if words_in_order?(name_parts, search_words) do
    # Find where the sequence starts
    start_pos = find_sequence_start(name_parts, search_words)
    case start_pos do
      0 -> 400     # Sequence starts at beginning
      1 -> 250     # Starts at second word
      2 -> 150     # Starts at third word
      _ -> 50
    end
  else
    0
  end
end

defp calculate_phrase_score(name_normalized, search_phrase) do
  if String.contains?(name_normalized, search_phrase) do
    # Find position of the phrase
    case find_phrase_position(name_normalized, search_phrase) do
      0 -> 600      # Phrase at beginning - highest
      pos when pos <= 10 -> 400
      pos when pos <= 20 -> 200
      _ -> 100
    end
  else
    0
  end
end

defp words_in_order?(name_parts, search_words) do
  find_sequence_start(name_parts, search_words) != nil
end

defp find_sequence_start(name_parts, search_words) do
  # Try each starting position
  Enum.find_index(name_parts, fn _ ->
    # Check if from this position, we can match all search words in order
    match_sequence?(name_parts, search_words, 0)
  end)
end

defp match_sequence?(_name_parts, [], _index), do: true
defp match_sequence?([], [_|_], _index), do: false
defp match_sequence?([n|name_tail], [s|search_tail], index) do
  if String.contains?(n, s) do
    match_sequence?(name_tail, search_tail, index + 1)
  else
    false
  end
end

defp find_phrase_position(name_normalized, search_phrase) do
  # Find position of phrase using split
  case String.split(name_normalized, search_phrase, parts: 2) do
    [before, _] -> String.length(before)
    _ -> nil
  end
end

# Simplified version that's guaranteed to work (no complex position calculations)
def search_simple_working(search_term, classes \\ []) do
  cleaned_term = String.trim(search_term)
  search_words = String.split(cleaned_term, " ")
  search_phrase = Enum.join(search_words, " ")
  
  # Get candidates with simple matching
  candidates = 
    from(i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^"%#{cleaned_term}%"),
      limit: 200
    )
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  
  # Simple sorting logic
  candidates
  |> Enum.sort_by(fn i ->
    name_norm = i.name
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    
    # Create a sort key as a tuple for natural ordering
    priority = cond do
      # Exact match (normalized)
      name_norm == search_phrase -> {1, 0}
      # Starts with search phrase
      String.starts_with?(name_norm, search_phrase) -> {2, 0}
      # Contains search phrase
      String.contains?(name_norm, search_phrase) -> {3, 0}
      # Contains all words in order
      all_words_in_order?(name_norm, search_words) -> {4, 0}
      # Contains all words (any order)
      Enum.all?(search_words, &String.contains?(name_norm, &1)) -> {5, 0}
      # Contains any word
      true -> {6, 0}
    end
    
    # Secondary sort: shorter names first (more specific)
    {priority, String.length(i.name), i.name}
  end)
  |> Enum.take(20)
end

defp all_words_in_order?(name_norm, search_words) do
  # Check if all search words appear in the correct order (non-contiguous)
  name_parts = String.split(name_norm, " ")
  is_subsequence(name_parts, search_words)
end

defp is_subsequence(_, []), do: true
defp is_subsequence([], _), do: false
defp is_subsequence([h|t], [s|st]) do
  if String.contains?(h, s) do
    is_subsequence(t, st)
  else
    is_subsequence(t, [s|st])
  end
end
  def search_robust(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)

    # Create patterns that ignore punctuation
    # "salt table" becomes patterns for "salt" and "table"
    words = String.split(cleaned_term, " ")

    # Build a query that matches each word, ignoring punctuation
    conditions =
      Enum.map(words, fn word ->
        dynamic([i], ilike(i.name, ^"%#{word}%"))
      end)

    combined_condition =
      Enum.reduce(conditions, fn cond, acc ->
        dynamic([i], ^cond and ^acc)
      end)

    candidates_query =
      from i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ^combined_condition,
        limit: 200

    candidates =
      candidates_query
      |> maybe_filter_by_classes(classes)
      |> Repo.all()

    # Rank: prefer matches where words appear in order
    search_phrase = Enum.join(words, " ")

    candidates
    |> Enum.sort_by(
      fn i ->
        name_lower = String.downcase(i.name)
        name_no_punct = String.replace(name_lower, ~r/[^\w\s]/, " ")

        cond do
          # Exact phrase match (ignoring punctuation)
          String.contains?(name_no_punct, search_phrase) -> 1000
          # All words present (any order)
          Enum.all?(words, &String.contains?(name_no_punct, &1)) -> 800
          # First word matches at beginning
          String.starts_with?(name_no_punct, List.first(words)) -> 600
          true -> 400
        end
      end,
      :desc
    )
    |> Enum.take(20)
  end

  def search_production(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)

    # Single efficient query to get candidates
    candidates =
      from(i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.name, ^"%#{cleaned_term}%"),
        limit: 200
      )
      |> maybe_filter_by_classes(classes)
      |> Repo.all()

    # Transform to list with sort keys (much faster than sorting full structs)
    candidates_with_scores =
      Enum.map(candidates, fn i ->
        name_lower = String.downcase(i.name)

        # Primary sort key (category)
        category =
          cond do
            name_lower == search_lower -> 1
            Regex.match?(~r/^#{Regex.escape(search_lower)}[, ]/, name_lower) -> 2
            String.starts_with?(name_lower, search_lower) -> 3
            Regex.match?(~r/\b#{Regex.escape(search_lower)}\b/, name_lower) -> 4
            true -> 5
          end

        # Secondary sort key (contains "with/without" penalty)
        has_modifier = Regex.match?(~r/(with|without|no|added)/, name_lower)

        # Tertiary sort key (length)
        length_penalty = String.length(name_lower)

        {i, category, has_modifier, length_penalty}
      end)

    # Sort: category asc, modifiers last, then by length
    sorted =
      Enum.sort(candidates_with_scores, fn
        {_, c1, m1, l1}, {_, c2, m2, l2} ->
          if c1 != c2 do
            # Lower category number = better
            c1 < c2
          else
            if m1 != m2 do
              # false (no modifier) comes before true (has modifier)
              not m1
            else
              # Shorter = better
              l1 < l2
            end
          end
      end)

    # Extract just the ingredients
    Enum.take(Enum.map(sorted, fn {i, _, _, _} -> i end), 20)
  end

  def search_two_phase(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)

    # Phase 1: Search for exact prefix matches (starts with the term)
    phase1_results =
      from(i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.name, ^"#{cleaned_term}%"),
        limit: 20
      )
      |> maybe_filter_by_classes(classes)
      |> Repo.all()

    # Phase 2: If phase 1 has enough results, return them
    if length(phase1_results) >= 10 do
      phase1_results
    else
      # Phase 3: Get remaining results, but exclude common noisy patterns
      remaining_needed = 20 - length(phase1_results)

      # Get contains matches, explicitly excluding "with salt", "no salt added", etc.
      exclude_patterns = ["with %", "without %", "no % added", "%added %"]

      base_query =
        from i in Ingredient,
          where: not is_nil(i.name),
          where: i.category_id not in ^get_second_layer_foods_ids(),
          where: ilike(i.name, ^"%#{cleaned_term}%"),
          where: i.id not in ^Enum.map(phase1_results, & &1.id),
          # Get extra to filter
          limit: ^remaining_needed * 2

      # Apply exclusions for noisy patterns
      filtered_query =
        Enum.reduce(exclude_patterns, base_query, fn pattern, q ->
          from i in q, where: not ilike(i.name, ^pattern)
        end)

      phase2_results =
        filtered_query
        |> maybe_filter_by_classes(classes)
        |> Repo.all()
        |> Enum.take(remaining_needed)

      phase1_results ++ phase2_results
    end
  end

  def search_weighted(search_term, classes \\ []) do
    if(search_term == "") do
      []
    else
      cleaned_term = String.trim(search_term)
      search_lower = String.downcase(cleaned_term)

      query =
        from i in Ingredient,
          where: not is_nil(i.name),
          where: i.category_id not in ^get_second_layer_foods_ids(),
          where: ilike(i.name, ^"%#{cleaned_term}%"),
          limit: 100

      candidates =
        query
        |> maybe_filter_by_classes(classes)
        |> Repo.all()

      candidates
      |> Enum.map(fn i ->
        name_lower = String.downcase(i.name)

        score =
          cond do
            # Perfect match (100 points)
            name_lower == search_lower -> 100
            # Starts with exact word (90 points)
            Regex.match?(~r/^#{Regex.escape(search_lower)}(?=[,\s]|$)/, name_lower) -> 90
            # Starts with prefix (80 points)
            String.starts_with?(name_lower, search_lower) -> 80
            # Contains as word (60 points)
            Regex.match?(~r/\b#{Regex.escape(search_lower)}\b/, name_lower) -> 60
            # Contains as substring (40 points)
            true -> 40
          end

        # Position bonus: earlier is better
        position = find_position(name_lower, search_lower)

        position_bonus =
          case position do
            0 -> 10
            p when p <= 5 -> 5
            _ -> 0
          end

        # Length bonus: shorter, more specific names get boost
        length_bonus = if String.length(name_lower) < 20, do: 5, else: 0

        {i, score + position_bonus + length_bonus}
      end)
      |> Enum.sort_by(fn {_i, score} -> -score end)
      |> Enum.map(fn {i, _score} -> i end)
      |> Enum.take(20)
    end
  end

  defp find_position(string, substring) do
    case :binary.match(string, substring) do
      {pos, _len} -> pos
      :nomatch -> nil
    end
  end

  def search_fixed(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)

    # Get candidates using multiple strategies
    query =
      from i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.name, ^"%#{cleaned_term}%"),
        limit: 200

    candidates =
      query
      |> maybe_filter_by_classes(classes)
      |> Repo.all()

    # Sort with explicit priority
    candidates
    |> Enum.sort_by(fn i ->
      name_lower = String.downcase(i.name)

      # Calculate priority (lower number = higher priority)
      priority =
        cond do
          # PRIORITY 1: Name starts with search term (exact word)
          Regex.match?(~r/^#{Regex.escape(search_lower)}(?=[,\s]|$)/, name_lower) ->
            1

          # PRIORITY 2: Name starts with search term as prefix
          String.starts_with?(name_lower, search_lower) ->
            2

          # PRIORITY 3: Contains as a separate word
          Regex.match?(~r/\b#{Regex.escape(search_lower)}\b/, name_lower) ->
            3

          # PRIORITY 4: Contains anywhere else
          true ->
            4
        end

      # Secondary sort: shorter names preferred for same priority
      {priority, String.length(name_lower), name_lower}
    end)
    |> Enum.take(20)
  end

  @doc """
  Simple, predictable search that puts exact matches first
  """
  def search(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)

    # Get all potential matches
    query =
      from i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.name, ^"%#{cleaned_term}%"),
        limit: 200

    query = maybe_filter_by_classes(query, classes)
    candidates = Repo.all(query)

    # Split into three categories
    {exact_matches, starts_with_matches, other_matches} =
      partition_results(candidates, search_lower)

    # Combine: exact matches first, then starts with, then others
    (exact_matches ++ starts_with_matches ++ other_matches)
    |> Enum.take(20)
  end

  defp partition_results(candidates, search_term) do
    Enum.reduce(candidates, {[], [], []}, fn ingredient, {exact, starts, other} ->
      name_lower = String.downcase(ingredient.name)

      cond do
        # Exact match (or exact with comma/space)
        name_lower == search_term ->
          {[ingredient | exact], starts, other}

        name_lower == "#{search_term}," ->
          {[ingredient | exact], starts, other}

        name_lower == "#{search_term} " ->
          {[ingredient | exact], starts, other}

        name_lower == "#{search_term}, " ->
          {[ingredient | exact], starts, other}

        # Starts with search term (but not exact)
        String.starts_with?(name_lower, search_term) ->
          {exact, [ingredient | starts], other}

        # Everything else
        true ->
          {exact, starts, [ingredient | other]}
      end
    end)
  end

  @doc """
  For select components - returns only id and name
  """
  def search_for_select(search_term, classes \\ []) do
    results = search(search_term, classes)
    Enum.map(results, fn i -> %{id: i.id, name: i.name} end)
  end

  # Simple search that prioritizes exact word boundaries
  def search_with_priority(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)

    # Build a query that prioritizes exact matches
    query =
      from i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.name, ^"%#{cleaned_term}%"),
        order_by: [
          desc:
            fragment(
              """
                CASE 
                  WHEN LOWER(?) = LOWER(?) THEN 3
                  WHEN LOWER(?) LIKE LOWER(?) || ',%' THEN 2
                  WHEN LOWER(?) LIKE LOWER(?) || ' %' THEN 2
                  WHEN LOWER(?) LIKE LOWER(?) || '%' THEN 1
                  ELSE 0
                END
              """,
              i.name,
              ^cleaned_term,
              i.name,
              ^cleaned_term,
              i.name,
              ^cleaned_term,
              i.name,
              ^cleaned_term
            ),
          asc: i.name
        ],
        limit: 20

    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # Helper functions
  defp maybe_filter_by_classes(query, nil), do: query
  defp maybe_filter_by_classes(query, []), do: query
  defp maybe_filter_by_classes(query, [""]), do: query

  defp maybe_filter_by_classes(query, classes) do
    from i in query, where: i.food_class in ^classes
  end

  defp get_second_layer_foods_ids do
    []
  end
end
