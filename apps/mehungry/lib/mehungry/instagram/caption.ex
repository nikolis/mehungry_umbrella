defmodule Mehungry.Instagram.Caption do
  @moduledoc """
  Builds Instagram captions for recipes, keeping within Instagram's
  2200-character caption limit. When a recipe is too long, whole sections are
  dropped (nutrients first, then instructions) before hard-truncating.
  """

  @max_length 2200
  @hashtag "#m3hungry"
  @suffix "\n\n" <> @hashtag

  def build(recipe) do
    sections =
      [
        header(recipe),
        ingredients(recipe),
        instructions(recipe),
        nutrients(recipe)
      ]
      |> Enum.reject(&(&1 == ""))

    fit(sections)
  end

  @doc """
  Formats a quantity/amount for display. Instagram captions historically used
  `Float.to_string`, which crashes on integers coming out of jsonb.
  """
  def format_number(nil), do: ""
  def format_number(n) when is_integer(n), do: Integer.to_string(n)

  def format_number(n) when is_float(n) do
    rounded = Float.round(n, 2)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      Float.to_string(rounded)
    end
  end

  defp header(recipe) do
    [recipe.title, recipe.description]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp ingredients(recipe) do
    items = Map.get(recipe, :recipe_ingredients) || []

    lines =
      Enum.map(items, fn ri ->
        [format_number(ri.quantity), ri.measurement_unit.name, ri.ingredient.name]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")
      end)

    section("Ingredients", lines)
  end

  defp instructions(recipe) do
    steps = Map.get(recipe, :steps) || []

    lines =
      Enum.map(steps, fn step ->
        [Map.get(step, :title), Map.get(step, :description)]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n")
      end)

    section("Instructions", lines)
  end

  defp nutrients(recipe) do
    entries = Map.get(recipe, :nutrients) || %{}

    lines =
      entries
      |> Enum.reject(fn {_, whole} -> is_nil(whole["amount"]) end)
      |> Enum.map(fn {_, whole} ->
        [whole["name"], format_number(whole["amount"]), whole["measurement_unit"]]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")
      end)

    section("Nutrients", lines)
  end

  defp section(_title, []), do: ""
  defp section(title, lines), do: title <> "\n\n" <> Enum.join(lines, "\n")

  # Drop trailing sections (nutrients, then instructions) until the caption
  # fits; never drop the header + ingredients before hard-truncating.
  defp fit(sections) do
    body = Enum.join(sections, "\n\n")
    caption = body <> @suffix

    cond do
      String.length(caption) <= @max_length ->
        caption

      length(sections) > 2 ->
        fit(List.delete_at(sections, -1))

      true ->
        budget = @max_length - String.length(@suffix) - 1
        String.slice(body, 0, budget) <> "…" <> @suffix
    end
  end
end
