defmodule Mehungry.FoodData.GutenbergImporter do
  @moduledoc """
  Imports recipes from public-domain, English-language Project Gutenberg
  cookbooks (see `Mehungry.FoodData.Gutenberg.Catalog`) into the Food context.

  Like `FoodData.MyPlateImporter`, this is a thin adapter: given one recipe block
  (already extracted from a book by `FoodData.Gutenberg.BookParser`) it maps the
  block into the normalized ingredient shape and hands the matching off to the
  shared `FoodData.RecipeIngredientResolver`. Gutenberg's ingredient lines are
  free text (`"1/2 pound of beef bones"`), so each is run through the same
  `FoodData.MyPlate.IngredientParser` the MyPlate path uses — it is a generic
  free-text ingredient-line parser, not MyPlate-specific.

  ## Ingredients can be empty — by design

  Many century-old cookbooks (the `:numbered` books especially) write ingredients
  inline in the prose rather than as a list, so `recipe.ingredient_lines` is often
  `[]`. That's fine: the recipe still imports with its directions, and the
  **human reviewer adds the ingredients by hand** in the Create Recipe form.

  ## Attribution (required credit)

  These titles are public domain, but we voluntarily credit the source: the book
  title + author land in the recipe's `author`, and the Gutenberg landing page in
  `original_url` (shown as a "Source" link on the recipe Steps tab).

  ## Nutrition

  Not imported (these books predate nutrition labelling). `Food.create_recipe/1`
  recomputes `nutrients`/`badges` from the matched ingredients
  (`RecipePutNutrientsWorker`), keeping these recipes consistent with the rest of
  the app.

  ## Return value

  `build_recipe_attrs/3` → `{:ok, attrs, unmatched}` — always `:ok` (even with
  zero matches) so the review form can present whatever was resolved and list the
  rest for the admin to fix.
  """

  alias Mehungry.FoodData.Gutenberg.Catalog
  alias Mehungry.FoodData.MyPlate.IngredientParser
  alias Mehungry.FoodData.RecipeIngredientResolver

  @doc """
  Builds `Recipe.changeset/2`-ready attrs from one parsed Gutenberg `recipe`
  block and its source `book` (a `Catalog` entry), without saving.
  """
  def build_recipe_attrs(recipe, book, user_id) do
    {resolved, unmatched} =
      recipe.ingredient_lines
      |> List.wrap()
      |> Enum.map(&IngredientParser.parse(&1, nil))
      |> RecipeIngredientResolver.resolve_ingredients()

    # Seed each matched ingredient's virtual `unit_selection` so the Create
    # Recipe form's unit dropdown shows the resolved choice (same as MyPlate).
    recipe_ingredients = Enum.map(resolved, &put_unit_selection/1)

    attrs = %{
      title: titleize(recipe.title),
      author: attribution(book),
      original_url: Catalog.book_url(book.id),
      # Provenance marker so Gutenberg imports can be group-managed (Food.*_by_source).
      source: "gutenberg",
      difficulty: 1,
      # These books carry no prep/cook times or servings; the schema requires the
      # times, so default to 0 (same as the other importers do for missing times).
      cooking_time_lower_limit: 0,
      cooking_time_upper_limit: 0,
      preperation_time_lower_limit: 0,
      preperation_time_upper_limit: 0,
      language_name: "En",
      user_id: user_id,
      # Staged private: best-effort extraction from century-old prose needs a
      # human pass before going public. The admin flips this in the review form
      # once the recipe is curated.
      private: true,
      description: description(recipe, book),
      steps: build_steps(recipe.directions),
      recipe_ingredients: recipe_ingredients
    }

    {:ok, attrs, unmatched}
  end

  # Encodes the resolved unit as the form's `unit_selection` (a positive
  # measurement_unit_id, or a negated description-only ingredient_portion_id).
  defp put_unit_selection(%{measurement_unit_id: mu_id} = ri) when is_integer(mu_id),
    do: Map.put(ri, :unit_selection, mu_id)

  defp put_unit_selection(%{ingredient_portion_id: pid} = ri) when is_integer(pid),
    do: Map.put(ri, :unit_selection, -pid)

  defp put_unit_selection(ri), do: ri

  # Description seeds the original-language subtitle (if any) + a book credit line.
  defp description(recipe, book) do
    [recipe.subtitle, "From #{book.title} by #{book.author} (public domain)."]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" — ")
  end

  defp attribution(book) do
    "#{book.title} by #{book.author} — Project Gutenberg (public domain)"
  end

  # ALL-CAPS book titles read as shouting; present them in Title Case. Keeps
  # short connective words lowercase for readability.
  @minor_words ~w(of the and or with a an in to for alla alle al di du de la le)
  defp titleize(title) do
    title
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.with_index()
    |> Enum.map(fn
      {word, 0} -> capitalize(word)
      {word, _} -> if word in @minor_words, do: word, else: capitalize(word)
    end)
    |> Enum.join(" ")
  end

  defp capitalize(word) do
    case String.split(word, "'", parts: 2) do
      [head, tail] -> String.capitalize(head) <> "'" <> tail
      [single] -> String.capitalize(single)
    end
  end

  # Split a prose directions body into sentence-sized steps (same as MyPlate).
  defp build_steps(directions) when is_binary(directions) and directions != "" do
    directions
    |> String.split(~r/(?<=[.!?])\s+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map(fn {sentence, index} -> %{index: index, description: sentence} end)
  end

  defp build_steps(_), do: []
end
