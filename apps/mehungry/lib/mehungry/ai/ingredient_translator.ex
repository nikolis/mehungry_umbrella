defmodule Mehungry.AI.IngredientTranslator do
  @moduledoc false

  require Logger

  @model "claude-sonnet-4-6"

  @doc """
  Translates a list of %{id: integer, name: string} maps into Greek.
  Returns {:ok, %{ingredient_id => greek_name}} or {:error, reason}.
  """
  def translate_to_greek(ingredients) when is_list(ingredients) do
    name_to_id = Map.new(ingredients, fn %{id: id, name: name} -> {name, id} end)
    names = Map.keys(name_to_id)

    system = """
    You are a Greek culinary expert helping localize a recipe app for Greek home cooks.

    The ingredient names come from the USDA food database, which uses a very specific technical
    naming convention: "Primary food, qualifier, qualifier, preparation method, fat trim level..."
    For example: "Chicken, broilers or fryers, breast, meat only, cooked, roasted" or
    "Oil, olive, salad or cooking" or "Beef, chuck, arm pot roast, separable lean only, trimmed to 0\" fat, choice, cooked, braised".

    Your task is to produce the name a Greek home cook would use when writing a recipe — the same
    vocabulary found on popular Greek recipe sites like akispetretzikis.com, gastronomos.gr, and argiro.gr.

    Rules:
    - Extract the CORE ingredient and use the everyday Greek kitchen name. Ignore USDA qualifiers
      about fat trim levels, cooking methods, brand specifics, and preparation states unless they
      are genuinely meaningful to a cook (e.g. "smoked" or "dried" often matter; "trimmed to 0.25 inch fat" never does).
    - Use the nominative singular form of Greek nouns (e.g. "σκόρδο" not "σκόρδου").
    - Prefer the short, recognizable name: "ελαιόλαδο" not "λάδι ελιάς, για σαλάτα ή μαγείρεμα".
    - For cuts of meat, use the Greek butcher name where one exists (e.g. "μπριζόλα χοιρινή",
      "μοσχαρίσιο φιλέτο", "κοτόπουλο μπούτι").
    - For processed or highly specific items with no clear Greek equivalent, give the closest
      meaningful Greek culinary term rather than a literal word-for-word translation.
    - For branded or very American-specific products, give the Greek equivalent category
      (e.g. "Fast food, pizza" → "πίτσα").

    Return ONLY a valid JSON object mapping each original English name to its Greek culinary name.
    No markdown, no explanation, no extra keys.

    Examples of the style expected:
    {
      "Chicken, broilers or fryers, breast, meat only, cooked, roasted": "στήθος κοτόπουλου",
      "Oil, olive, salad or cooking": "ελαιόλαδο",
      "Cheese, feta": "φέτα",
      "Tomatoes, red, ripe, raw, year round average": "ντομάτα",
      "Beef, ground, 80% lean meat / 20% fat, patty, cooked, pan-broiled": "κιμάς βοδινός",
      "Lemon juice, raw": "χυμός λεμονιού",
      "Alcoholic beverage, wine, table, white": "λευκό κρασί",
      "Spices, oregano, dried": "ρίγανη",
      "Nuts, walnuts, english": "καρύδια"
    }
    """

    user =
      "Translate these USDA ingredient names to Greek culinary names:\n#{Jason.encode!(names)}"

    case call_api(system, user) do
      {:ok, text} ->
        parse_translation_map(text, name_to_id)

      error ->
        error
    end
  end

  defp parse_translation_map(text, name_to_id) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        id_to_greek =
          map
          |> Enum.flat_map(fn {english_name, greek_name} ->
            case Map.get(name_to_id, english_name) do
              nil -> []
              id -> [{id, greek_name}]
            end
          end)
          |> Map.new()

        {:ok, id_to_greek}

      _ ->
        Logger.warning("IngredientTranslator: failed to parse response: #{inspect(text)}")
        {:error, "Could not parse translation response"}
    end
  end

  defp call_api(system, user) do
    case Mehungry.AI.Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 4096
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end
end
