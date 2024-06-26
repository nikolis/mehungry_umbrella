defmodule Mehungry.Search.RecipeSearch do
  @moduledoc false

  import Ecto.Query

  def run(query, search_string) do
    _run(query, normalize(search_string))
  end

  defmacro matching_recipe_ids_and_ranks(search_string) do
    quote do
      fragment(
        """
        SELECT recipe_search.id AS id,
        ts_rank(
          recipe_search.document, plainto_tsquery(unaccent(?))
        ) AS rank
        FROM recipe_search
        WHERE recipe_search.document @@ plainto_tsquery(unaccent(?))
        OR recipe_search.title ILIKE ?
        """,
        ^unquote(search_string),
        ^unquote(search_string),
        ^"%#{unquote(search_string)}%"
      )
    end
  end

  defp _run(query, ""), do: query

  defp _run(query, search_string) do
    from recipe in query,
      join: id_and_rank in matching_recipe_ids_and_ranks(search_string),
      on: id_and_rank.id == recipe.id,
      order_by: [desc: id_and_rank.rank]
  end

  defp normalize(search_string) do
    search_string
    |> String.downcase()
    |> String.replace("gluten free", "gluten-free")
    |> String.replace("dairy free", "dairy-free")
    |> String.replace("sugar free", "sugar-free")
    |> String.replace("meatless", "no-meat")
    |> String.replace("vegetarian", "no-meat")
    |> String.replace(~r/\n/, " ")
    |> String.replace(~r/\t/, " ")
    |> String.replace(~r/\s{2,}/, " ")
    |> String.trim()
  end
end
