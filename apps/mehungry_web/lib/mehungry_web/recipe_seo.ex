defmodule MehungryWeb.RecipeSeo do
  @moduledoc """
  Shared SEO builders for recipe-detail pages.

  Every route that renders a single recipe (`/browse/:id`, `/home/:id`,
  `/show_recipe/:id`, …) canonicalizes to `/browse/:id`, but each should still
  emit the same rich meta description + schema.org `Recipe` JSON-LD so the page
  is self-describing if a crawler lands on it directly. That logic lives here
  once and is called from each LiveView rather than copied per surface.

  `assign/2` is the one-call entry point: it sets `:page_title`,
  `:page_seo_data` (→ canonical `/browse/:id`), `:page_description`, and
  `:recipe_jsonld`, which `head.html.heex` reads off `@conn.assigns` on the
  disconnected render.
  """

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Assigns the full recipe SEO bundle (title, seo data, description, JSON-LD)
  onto the socket for a given recipe.
  """
  def assign(socket, recipe) do
    title = recipe.title <> " — Instructions and Nutrition Facts"

    socket
    |> assign(:page_title, title)
    |> assign(:page_seo_data, %{
      title: title,
      img: recipe.image_url,
      id: Integer.to_string(recipe.id)
    })
    |> assign(:page_description, description(recipe))
    |> assign(:recipe_jsonld, jsonld(recipe))
  end

  @doc """
  A meta-description string for a recipe: its own description (or title) plus
  servings / cook-time, suffixed with the brand tag.
  """
  def description(recipe) do
    base =
      if recipe.description && String.length(recipe.description) > 10 do
        String.slice(recipe.description, 0, 140)
      else
        "#{recipe.title} recipe"
      end

    extras = []

    extras =
      if recipe.servings && recipe.servings > 0,
        do: ["#{recipe.servings} servings" | extras],
        else: extras

    extras =
      if recipe.cooking_time_lower_limit && recipe.cooking_time_lower_limit > 0,
        do: ["ready in #{recipe.cooking_time_lower_limit} min" | extras],
        else: extras

    suffix = if extras != [], do: " — " <> Enum.join(Enum.reverse(extras), ", "), else: ""
    base <> suffix <> ". Full nutrition facts on M3Hungry."
  end

  @doc """
  A schema.org `Recipe` structured-data map for Google rich results. Only
  emits fields backed by real data (never fabricated numbers).
  """
  def jsonld(recipe) do
    base = %{
      "@context" => "https://schema.org",
      "@type" => "Recipe",
      "name" => recipe.title,
      "url" => "https://www.m3hungry.com/browse/#{recipe.id}",
      "description" => recipe.description || recipe.title
    }

    base = if recipe.image_url, do: Map.put(base, "image", recipe.image_url), else: base

    base =
      if recipe.cooking_time_lower_limit && recipe.cooking_time_lower_limit > 0 do
        Map.put(base, "cookTime", "PT#{recipe.cooking_time_lower_limit}M")
      else
        base
      end

    base =
      if recipe.preperation_time_lower_limit && recipe.preperation_time_lower_limit > 0 do
        Map.put(base, "prepTime", "PT#{recipe.preperation_time_lower_limit}M")
      else
        base
      end

    base =
      if recipe.servings && recipe.servings > 0 do
        Map.put(base, "recipeYield", "#{recipe.servings} servings")
      else
        base
      end

    # totalTime — prep + cook when both known (Google asks for it explicitly).
    base =
      case total_time_minutes(recipe) do
        nil -> base
        minutes -> Map.put(base, "totalTime", "PT#{minutes}M")
      end

    # datePublished — helps Google judge freshness; derived from the row's insert.
    base =
      case recipe.inserted_at do
        %NaiveDateTime{} = dt -> Map.put(base, "datePublished", NaiveDateTime.to_iso8601(dt))
        %DateTime{} = dt -> Map.put(base, "datePublished", DateTime.to_iso8601(dt))
        _ -> base
      end

    # nutrition — a NutritionInformation block from the recipe's own USDA-backed
    # totals (the thing the app is built on), expressed per serving. Only emitted
    # when we actually have calories, so we never assert fabricated numbers.
    base =
      case jsonld_nutrition(recipe) do
        nil -> base
        nutrition -> Map.put(base, "nutrition", nutrition)
      end

    # author — recipe.author (free-text) falls back to the recipe owner's name.
    base =
      case jsonld_author(recipe) do
        nil -> base
        name -> Map.put(base, "author", %{"@type" => "Person", "name" => name})
      end

    # recipeCuisine — note the schema field is the misspelled `cousine`.
    base =
      if is_binary(recipe.cousine) and String.trim(recipe.cousine) != "" do
        Map.put(base, "recipeCuisine", String.trim(recipe.cousine))
      else
        base
      end

    # recipeIngredient — one free-text line per ingredient ("2 cup Flour").
    base =
      case jsonld_ingredients(recipe) do
        [] -> base
        lines -> Map.put(base, "recipeIngredient", lines)
      end

    # keywords — comma-separated hashtag titles.
    base =
      case jsonld_keywords(recipe) do
        nil -> base
        keywords -> Map.put(base, "keywords", keywords)
      end

    case recipe.steps do
      steps when is_list(steps) and steps != [] ->
        instructions =
          steps
          |> Enum.with_index(1)
          |> Enum.map(fn {step, position} ->
            # `name` is a per-step field Google flags as missing; use the step
            # title, falling back to "Step N" so every HowToStep is named.
            name =
              if is_binary(step.title) and String.trim(step.title) != "",
                do: String.trim(step.title),
                else: "Step #{position}"

            %{
              "@type" => "HowToStep",
              "name" => name,
              "text" => step.description || step.title || name
            }
          end)

        Map.put(base, "recipeInstructions", instructions)

      _ ->
        base
    end
  end

  # Sum of prep + cook lower limits (minutes), or nil when neither is set.
  defp total_time_minutes(recipe) do
    prep =
      if is_integer(recipe.preperation_time_lower_limit),
        do: recipe.preperation_time_lower_limit,
        else: 0

    cook =
      if is_integer(recipe.cooking_time_lower_limit), do: recipe.cooking_time_lower_limit, else: 0

    case prep + cook do
      0 -> nil
      total -> total
    end
  end

  # schema.org NutritionInformation from the recipe's stored (whole-recipe) USDA
  # totals, divided to a per-serving basis. `recipe.nutrients` is the aggregate
  # tree `Mehungry.NutrientUtils.macro_summary/1` already consumes everywhere
  # else (calendar, share cards), so we reuse it rather than recompute. Returns
  # nil when there's no energy value — we only publish real numbers.
  defp jsonld_nutrition(recipe) do
    nutrients = recipe.nutrients

    if is_map(nutrients) and map_size(nutrients) > 0 do
      summary = Mehungry.NutrientUtils.macro_summary(nutrients)

      servings =
        if is_integer(recipe.servings) and recipe.servings > 0, do: recipe.servings, else: 1

      if summary.energy_kcal > 0 do
        per = fn value -> value / servings end

        %{
          "@type" => "NutritionInformation",
          "servingSize" => "1 serving",
          "calories" => "#{round(per.(summary.energy_kcal))} kcal",
          "proteinContent" => "#{Float.round(per.(summary.protein_g), 1)} g",
          "fatContent" => "#{Float.round(per.(summary.fat_g), 1)} g",
          "saturatedFatContent" => "#{Float.round(per.(summary.saturated_fat_g), 1)} g",
          "carbohydrateContent" => "#{Float.round(per.(summary.carbs_g), 1)} g",
          "sugarContent" => "#{Float.round(per.(summary.sugars_g), 1)} g",
          "fiberContent" => "#{Float.round(per.(summary.fiber_g), 1)} g",
          "sodiumContent" => "#{round(per.(summary.sodium_mg))} mg"
        }
      end
    end
  end

  defp jsonld_author(recipe) do
    cond do
      is_binary(recipe.author) and String.trim(recipe.author) != "" ->
        String.trim(recipe.author)

      match?(%{name: name} when is_binary(name), recipe.user) and
          String.trim(recipe.user.name) != "" ->
        String.trim(recipe.user.name)

      true ->
        nil
    end
  end

  defp jsonld_ingredients(recipe) do
    case recipe.recipe_ingredients do
      ingredients when is_list(ingredients) ->
        ingredients
        |> Enum.map(&jsonld_ingredient_line/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp jsonld_ingredient_line(recipe_ingredient) do
    name =
      case recipe_ingredient.ingredient do
        %{name: n} when is_binary(n) -> n |> Mehungry.Utils.remove_parenthesis() |> String.trim()
        _ -> nil
      end

    if name && name != "" do
      qty = jsonld_quantity(recipe_ingredient.quantity)
      unit = Mehungry.Food.RecipeIngredient.unit_label(recipe_ingredient)

      [qty, unit, name]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
    end
  end

  defp jsonld_quantity(nil), do: nil

  defp jsonld_quantity(quantity) when is_float(quantity) do
    if quantity == Float.round(quantity),
      do: quantity |> trunc() |> Integer.to_string(),
      else: Float.to_string(quantity)
  end

  defp jsonld_quantity(quantity), do: to_string(quantity)

  defp jsonld_keywords(recipe) do
    case recipe.recipe_hashtags do
      hashtags when is_list(hashtags) ->
        titles =
          hashtags
          |> Enum.map(fn
            %{hashtag: %{title: t}} when is_binary(t) -> String.trim(t)
            _ -> nil
          end)
          |> Enum.reject(&(&1 in [nil, ""]))

        case titles do
          [] -> nil
          list -> Enum.join(list, ", ")
        end

      _ ->
        nil
    end
  end
end
