defmodule Mehungry.AI.RecipeUrlImport do
  @moduledoc """
  Imports a recipe from an arbitrary URL into the AI recipe assistant.

  Two stages:

    1. Fetch the page and extract the source recipe. The primary extractor reads
       schema.org JSON-LD (`<script type="application/ld+json">`), which most recipe
       sites embed for SEO; when none is present we fall back to the page's stripped
       text and let the agent extract from it.
    2. Hand the extracted source to `Mehungry.AI.Agents.RecipeAgent` in *import mode*,
       which reproduces the ingredient list as exactly as possible, rewrites the steps
       in its own words (so they are not a verbatim copy), and authors a fresh title
       and description.

  Returns the same `{:ok, attrs, unmatched}` tuple as the rest of the AI recipe path,
  so the LiveView persists it through the existing `Food.create_recipe/1` flow. `attrs`
  carries the source `"original_url"`.

  The HTTP fetch goes through a configurable adapter seam
  (`:recipe_url_http_adapter`, defaulting to `&HTTPoison.get/3`) so tests can stub it.
  """

  alias Mehungry.AI.Agents.RecipeAgent

  # A browser-like UA — many recipe sites 403 an empty/default user agent.
  @user_agent "Mozilla/5.0 (compatible; MehungryBot/1.0; +https://www.m3hungry.com)"
  @max_raw_chars 12_000

  @doc """
  Fetches the recipe at `url`, reproduces it via `RecipeAgent` in import mode, and
  returns `{:ok, attrs, unmatched}` ready for `Food.create_recipe/1`, or `{:error, reason}`.
  """
  def run(url) do
    with {:ok, source} <- fetch_and_extract(url),
         {:ok, attrs, unmatched} <-
           RecipeAgent.run(source[:title] || "imported recipe", import_source: source) do
      {:ok, Map.put(attrs, "original_url", url), unmatched}
    end
  end

  @doc """
  Fetches the URL and extracts a source-recipe map.

  Returns `{:ok, source}` where `source` is either

    * `%{title, ingredients: [str], instructions: [str], description, source_url, mode: :structured}`
      (schema.org JSON-LD Recipe found), or
    * `%{raw_text: str, source_url, mode: :raw}` (fallback — stripped page text).

  Returns `{:error, :invalid_url}`, `{:error, {:http, status}}`, or `{:error, reason}`.
  """
  def fetch_and_extract(url) do
    with :ok <- validate_url(url),
         {:ok, html} <- fetch(url) do
      {:ok, extract(html, url)}
    end
  end

  # ── url validation ──────────────────────────────────────────────────────────

  defp validate_url(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, :invalid_url}
    end
  end

  defp validate_url(_), do: {:error, :invalid_url}

  # ── fetch ─────────────────────────────────────────────────────────────────────

  defp fetch(url) do
    adapter = Application.get_env(:mehungry, :recipe_url_http_adapter, &HTTPoison.get/3)
    headers = [{"User-Agent", @user_agent}]
    opts = [follow_redirect: true, recv_timeout: 15_000]

    case adapter.(String.trim(url), headers, opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}

      other ->
        {:error, other}
    end
  end

  # ── extraction ──────────────────────────────────────────────────────────────

  defp extract(html, url) do
    case extract_json_ld_recipe(html) do
      {:ok, recipe} -> structured_source(recipe, url)
      :error -> %{raw_text: raw_text(html), source_url: url, mode: :raw}
    end
  end

  defp structured_source(recipe, url) do
    %{
      title: string_or_nil(recipe["name"]),
      description: string_or_nil(recipe["description"]),
      ingredients: ingredient_lines(recipe["recipeIngredient"]),
      instructions: instruction_lines(recipe["recipeInstructions"]),
      source_url: url,
      mode: :structured
    }
  end

  # Pull every <script type="application/ld+json"> block, decode it, and search for
  # an object whose @type is (or includes) "Recipe" — including inside @graph arrays
  # and top-level arrays.
  defp extract_json_ld_recipe(html) do
    ~r/<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/is
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [json] -> Jason.decode(json) end)
    |> Enum.flat_map(fn
      {:ok, decoded} -> candidate_nodes(decoded)
      _ -> []
    end)
    |> Enum.find(&recipe_node?/1)
    |> case do
      nil -> :error
      recipe -> {:ok, recipe}
    end
  end

  # Flatten a decoded JSON-LD payload into the list of objects worth inspecting:
  # the node itself, any list elements, and any @graph children.
  defp candidate_nodes(list) when is_list(list), do: Enum.flat_map(list, &candidate_nodes/1)

  defp candidate_nodes(%{"@graph" => graph} = node) when is_list(graph),
    do: [node | Enum.flat_map(graph, &candidate_nodes/1)]

  defp candidate_nodes(%{} = node), do: [node]
  defp candidate_nodes(_), do: []

  defp recipe_node?(%{"@type" => type}), do: type_recipe?(type)
  defp recipe_node?(_), do: false

  defp type_recipe?(type) when is_binary(type), do: String.downcase(type) == "recipe"
  defp type_recipe?(types) when is_list(types), do: Enum.any?(types, &type_recipe?/1)
  defp type_recipe?(_), do: false

  # recipeIngredient is a list of plain strings per schema.org.
  defp ingredient_lines(list) when is_list(list) do
    list
    |> Enum.map(&string_or_nil/1)
    |> Enum.reject(&is_nil/1)
  end

  defp ingredient_lines(str) when is_binary(str), do: ingredient_lines([str])
  defp ingredient_lines(_), do: []

  # recipeInstructions can be a string, a list of strings, a list of HowToStep
  # objects (with "text"), or HowToSection objects nesting itemListElement steps.
  defp instruction_lines(list) when is_list(list), do: Enum.flat_map(list, &instruction_lines/1)
  defp instruction_lines(str) when is_binary(str), do: [str] |> clean_lines()

  defp instruction_lines(%{"itemListElement" => steps}) when is_list(steps),
    do: instruction_lines(steps)

  defp instruction_lines(%{"text" => text}) when is_binary(text), do: clean_lines([text])
  defp instruction_lines(%{"name" => name}) when is_binary(name), do: clean_lines([name])
  defp instruction_lines(_), do: []

  defp clean_lines(lines) do
    lines
    |> Enum.map(&strip_html/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp raw_text(html) do
    html
    # Drop script/style contents entirely before stripping tags.
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, " ")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, " ")
    |> strip_html()
    |> String.slice(0, @max_raw_chars)
  end

  defp string_or_nil(str) when is_binary(str) do
    case strip_html(str) do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp string_or_nil(_), do: nil

  # Mirrors SpoonacularImporter.strip_html/1 — tag + common-entity removal.
  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""
end
