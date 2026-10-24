defmodule MehungryWeb.ProfessionalLive.ImportReviewSearch do
  @moduledoc """
  Tiny, dependency-free fuzzy ranking shared by the manual recipe-import review
  LiveViews (MyPlate / Gutenberg / UniTools), so the admin can **search the full
  recipe list** by title/slug and pick what to import, instead of stepping blindly
  through "next recipe".

  Ranking is pure `String.jaro_distance/2` + substring matching:

    * a substring hit (the whole search term appears in the text) ranks highest,
    * otherwise the best per-word Jaro similarity above `@jaro_threshold` counts,
    * **every** search term must match (AND), so "chicken soup" narrows the list
      rather than widening it.

  Scores are summed across terms so more/closer matches float to the top.
  """

  # Jaro similarity (0.0–1.0) at or above which a non-substring word is a "match".
  # Tuned so "carbonara" matches "carbonera" but unrelated words don't.
  @jaro_threshold 0.82

  @doc """
  Filters and ranks `items` against `query`, reading each item's searchable text
  via `text_fun`. Returns the matching items best-first; a blank query returns
  `items` unchanged (so the full list shows before the admin types).
  """
  def filter(items, query, text_fun) when is_function(text_fun, 1) do
    case search_terms(query) do
      [] ->
        items

      terms ->
        items
        |> Enum.map(fn item -> {score(normalize(text_fun.(item)), terms), item} end)
        |> Enum.reject(fn {score, _item} -> score <= 0.0 end)
        |> Enum.sort_by(fn {score, _item} -> score end, :desc)
        |> Enum.map(fn {_score, item} -> item end)
    end
  end

  defp search_terms(query) do
    query
    |> normalize()
    |> String.split(~r/\s+/, trim: true)
  end

  defp normalize(text), do: text |> to_string() |> String.downcase() |> String.trim()

  # Every term must match; a single miss drops the item (sum would be wrong anyway).
  defp score(text, terms) do
    Enum.reduce_while(terms, 0.0, fn term, acc ->
      case term_score(text, term) do
        s when s <= 0.0 -> {:halt, 0.0}
        s -> {:cont, acc + s}
      end
    end)
  end

  defp term_score(text, term) do
    if String.contains?(text, term), do: 2.0, else: best_word_jaro(text, term)
  end

  defp best_word_jaro(text, term) do
    best =
      text
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reduce(0.0, fn word, best -> max(best, String.jaro_distance(word, term)) end)

    if best >= @jaro_threshold, do: best, else: 0.0
  end
end
