# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  @moduledoc """
  USDA-style ingredient search with exact match priority
  """
  
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  @doc """
  USDA-style search that prioritizes exact matches and natural language
  """
  def search_usda_style(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Build the ranking using CASE statements in SQL
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("LOWER(?) LIKE LOWER(?)", i.name, ^"%#{cleaned_term}%"),
      select: %{
        id: i.id,
        name: i.name,
        description: i.description,
        food_class: i.food_class,
        category_id: i.category_id,
        measurement_unit_id: i.measurement_unit_id,
        inserted_at: i.inserted_at,
        updated_at: i.updated_at,
        # Calculate relevance score
        relevance: fragment("""
          CASE
            -- Exact match (highest priority)
            WHEN LOWER(?) = LOWER(?) THEN 100
            -- Starts with search term
            WHEN LOWER(?) LIKE LOWER(?) || '%' THEN 90
            -- Contains as whole word
            WHEN LOWER(?) ~ ('\\y' || LOWER(?) || '\\y') THEN 80
            -- Contains search term
            WHEN LOWER(?) LIKE LOWER(?) THEN 70
            -- Fallback
            ELSE 0
          END +
          -- Boost for Foundation/SR Legacy data types
          CASE
            WHEN ? IN ('Foundation', 'SR Legacy') THEN 10
            ELSE 0
          END
        """,
          i.name, ^cleaned_term,                                    # exact match
          i.name, ^cleaned_term,                                    # prefix match
          i.name, ^cleaned_term,                                    # word boundary
          i.name, ^cleaned_term,                                    # contains
          i.food_class                                              # data type boost
        )
      },
      order_by: [desc: :relevance, asc: i.name],
      limit: 20
    
    # Apply class filter if needed
    query = maybe_filter_by_classes(query, classes)
    
    # Execute and convert to proper Ingredient structs
    results = Repo.all(query)
    
    # Convert the selected fields back to Ingredient structs
    Enum.map(results, fn r ->
      %Ingredient{
        id: r.id,
        name: r.name,
        description: r.description,
        food_class: r.food_class,
        category_id: r.category_id,
        measurement_unit_id: r.measurement_unit_id,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    end)
  end

  @doc """
  Multi-tier search that progressively expands the search
  """
  def search_progressive(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Build a search that expands based on result count
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      select: %{
        id: i.id,
        name: i.name,
        description: i.description,
        food_class: i.food_class,
        category_id: i.category_id,
        measurement_unit_id: i.measurement_unit_id,
        rank: fragment("""
          CASE
            WHEN LOWER(?) = LOWER(?) THEN 1
            WHEN LOWER(?) LIKE LOWER(?) || '%' THEN 2
            WHEN LOWER(?) ~ ('\\y' || LOWER(?) || '\\y') THEN 3
            WHEN LOWER(?) LIKE ('%' || LOWER(?) || '%') THEN 4
            ELSE 5
          END
        """,
          i.name, ^cleaned_term,
          i.name, ^cleaned_term,
          i.name, ^cleaned_term,
          i.name, ^cleaned_term
        )
      },
      order_by: [asc: :rank, asc: i.name],
      limit: 20
    
    query = maybe_filter_by_classes(query, classes)
    results = Repo.all(query)
    
    # If we have enough exact matches, return them
    exact_matches = Enum.filter(results, fn r -> r.rank == 1 end)
    if length(exact_matches) >= 5 do
      # Return exact matches only
      exact_matches
    else
      # Return all results, but exact matches first
      results
    end
    |> Enum.map(fn r ->
      %Ingredient{
        id: r.id,
        name: r.name,
        description: r.description,
        food_class: r.food_class,
        category_id: r.category_id,
        measurement_unit_id: r.measurement_unit_id,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    end)
  end

  @doc """
  Pure Elixir ranking for complete control (no SQL CASE complexities)
  """
  def search_ranked_elixir(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Get candidate matches using simple LIKE
    candidate_query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("LOWER(?) LIKE LOWER(?)", i.name, ^"%#{cleaned_term}%"),
      limit: 100
    
    candidate_query = maybe_filter_by_classes(candidate_query, classes)
    candidates = Repo.all(candidate_query)
    
    # Rank in Elixir with USDA-style logic
    candidates
    |> Enum.map(fn ingredient ->
      score = calculate_usda_score(ingredient.name, search_lower, ingredient.food_class)
      {ingredient, score}
    end)
    |> Enum.sort_by(fn {_ingredient, score} -> -score end)  # Higher score first
    |> Enum.map(fn {ingredient, _score} -> ingredient end)
    |> Enum.take(20)
  end

  # USDA-style scoring function
  defp calculate_usda_score(name, search_term, food_class) do
    name_lower = String.downcase(name)
    
    cond do
      # Exact match (highest score)
      name_lower == search_term -> 100
      name_lower == "#{search_term}," -> 100
      name_lower == "#{search_term} " -> 100
      name_lower == "#{search_term}, " -> 100
      
      # Starts with search term
      String.starts_with?(name_lower, search_term) -> 90
      
      # Whole word match
      String.contains?(name_lower, " #{search_term} ") -> 85
      String.contains?(name_lower, " #{search_term},") -> 85
      String.ends_with?(name_lower, " #{search_term}") -> 85
      
      # Contains as part of a word
      String.contains?(name_lower, search_term) -> 70
      
      # Fallback
      true -> 50
    end
    # Add bonus for Foundation/SR Legacy data types
    |> add_data_type_bonus(food_class)
  end

  defp add_data_type_bonus(score, food_class) when food_class in ["Foundation", "SR Legacy"] do
    score + 5
  end
  defp add_data_type_bonus(score, _), do: score

  # Simple search that guarantees "Salt, table" appears first for "salt"
  def search_salt_optimized(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Special handling for common spices/seasonings
    exact_match_boost = fn name ->
      name_lower = String.downcase(name)
      cond do
        name_lower == search_lower -> 100
        name_lower == "#{search_lower}, table" -> 99
        name_lower == "#{search_lower}, ground" -> 98
        name_lower == "#{search_lower}, kosher" -> 97
        name_lower == "#{search_lower}, sea" -> 96
        true -> 0
      end
    end
    
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("LOWER(?) LIKE LOWER(?)", i.name, ^"%#{cleaned_term}%"),
      select: %{
        id: i.id,
        name: i.name,
        description: i.description,
        food_class: i.food_class,
        category_id: i.category_id,
        measurement_unit_id: i.measurement_unit_id,
        inserted_at: i.inserted_at,
        updated_at: i.updated_at,
        boost: fragment("CASE WHEN LOWER(?) = LOWER(?) THEN 1 ELSE 0 END", i.name, ^cleaned_term)
      },
      order_by: [desc: :boost, asc: i.name],
      limit: 20
    
    query = maybe_filter_by_classes(query, classes)
    results = Repo.all(query)
    
    Enum.map(results, fn r ->
      %Ingredient{
        id: r.id,
        name: r.name,
        description: r.description,
        food_class: r.food_class,
        category_id: r.category_id,
        measurement_unit_id: r.measurement_unit_id,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    end)
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
