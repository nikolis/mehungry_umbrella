# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  @doc """
  Search ingredients using the pre-processed search_name column
  This gives prefix-match priority and is very fast
  """
  def search(search_term, classes \\ []) do
    # Normalize the search term the same way we normalized the database
    normalized_term = Ingredient.normalize_string(search_term)
    
    # Return empty if normalized term is empty
    if normalized_term == "" do
      []
    else
      # Split into words for multi-word search
      search_words = String.split(normalized_term, " ")
      
      # Build query based on number of words
      case length(search_words) do
        1 ->
          # Single word: use prefix search for best performance
          search_single_word(normalized_term, classes)
        
        _ ->
          # Multiple words: search for phrase and individual words
          search_multi_word(search_words, normalized_term, classes)
      end
    end
  end
# lib/mehungry/food/ingredient_search.ex

def search2(search_term, classes \\ []) do
  normalized_term = Ingredient.normalize_string(search_term)
  
  if normalized_term == "" do
    []
  else
    query = from i in Ingredient,
      where: not is_nil(i.search_name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.search_name, ^"#{normalized_term}%"),
      order_by: [
        # Priority 1: Exact match
        desc: fragment("CASE WHEN ? = ? THEN 1 ELSE 0 END", i.search_name, ^normalized_term),
        # Priority 2: Shorter names first (more specific)
        asc: fragment("LENGTH(?)", i.search_name),
        # Priority 3: USDA data type (Foundation > SR Legacy > others)
        asc: fragment("""
          CASE i.food_class
            WHEN 'Foundation' THEN 1
            WHEN 'SR Legacy' THEN 2
            WHEN 'Survey (FNDDS)' THEN 3
            WHEN 'Experimental' THEN 4
            ELSE 5
          END
        """),
        # Priority 4: Alphabetical
        asc: i.name
      ],
      limit: 20
    
    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end
end
  defp search_single_word(search_term, classes) do
    query = from i in Ingredient,
      where: not is_nil(i.search_name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.search_name, ^"#{search_term}%"),
      order_by: [asc: i.search_name],
      limit: 20
    
    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  defp search_multi_word(search_words, normalized_term, classes) do
    # Step 1: Try to find exact phrase prefix matches
    phrase_query = from i in Ingredient,
      where: not is_nil(i.search_name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.search_name, ^"#{normalized_term}%"),
      limit: 10
    
    phrase_results = 
      phrase_query
      |> maybe_filter_by_classes(classes)
      |> Repo.all()
    
    # Step 2: If we have enough phrase matches, return them
    if length(phrase_results) >= 10 do
      phrase_results
    else
      # Step 3: Find other results that contain all words (any order)
      needed = 20 - length(phrase_results)
      
      # Build conditions for each word
      word_conditions = Enum.map(search_words, fn word ->
        dynamic([i], ilike(i.search_name, ^"%#{word}%"))
      end)
      
      all_words_condition = Enum.reduce(word_conditions, fn cond, acc ->
        dynamic([i], ^cond and ^acc)
      end)
      
      # Use ^needed to interpolate the variable
      other_query = from i in Ingredient,
        where: not is_nil(i.search_name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ^all_words_condition,
        where: i.id not in ^Enum.map(phrase_results, & &1.id),
        order_by: [asc: i.search_name],
        limit: ^needed  # ← FIXED: Added ^ here
      
      other_results = 
        other_query
        |> maybe_filter_by_classes(classes)
        |> Repo.all()
      
      phrase_results ++ other_results
    end
  end

  # Helper function for select dropdowns (returns only id and name)
  def search_for_select(search_term, classes \\ []) do
    results = search(search_term, classes)
    Enum.map(results, fn i -> %{id: i.id, name: i.name} end)
  end

  # Fallback: simple prefix search (always works, always fast)
  def search_prefix(search_term, classes \\ []) do
    normalized_term = Ingredient.normalize_string(search_term)
    
    query = from i in Ingredient,
      where: not is_nil(i.search_name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.search_name, ^"#{normalized_term}%"),
      order_by: [asc: i.search_name],
      limit: 20,
      select: [:id, :name]
    
    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # Simple version that only does prefix search (fastest, most reliable)
  def search_prefix_only(search_term, classes \\ []) do
    normalized_term = Ingredient.normalize_string(search_term)
    
    # If the normalized term is empty, return empty list
    if normalized_term == "" do
      []
    else
      query = from i in Ingredient,
        where: not is_nil(i.search_name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.search_name, ^"#{normalized_term}%"),
        order_by: [
          # Exact match boost
          desc: fragment("CASE WHEN ? = ? THEN 1 ELSE 0 END", i.search_name, ^normalized_term),
          # Shorter names first
          asc: fragment("LENGTH(?)", i.search_name)
        ],
        limit: 20
      
      query
      |> maybe_filter_by_classes(classes)
      |> Repo.all()
    end
  end

  # Helper functions
  defp maybe_filter_by_classes(query, nil), do: query
  defp maybe_filter_by_classes(query, []), do: query
  defp maybe_filter_by_classes(query, [""]), do: query
  defp maybe_filter_by_classes(query, classes) do
    from i in query, where: i.food_class in ^classes
  end

  defp get_second_layer_foods_ids do
    # Your existing logic for secondary IDs
    []
  end
end
