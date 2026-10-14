defmodule MehungryWeb.Api.V1.RecipeJSON do
  @moduledoc "Serializers for feed cards and full recipe detail (spec §4)."

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Food.{MeasurementUnit, RecipeIngredient}
  alias Mehungry.Food.Nutrition.FattyAcidMatcher
  alias MehungryWeb.Api.V1.UserJSON

  @doc """
  A feed card built from a `Post` (its `:reference` is the recipe). `ctx` carries
  viewer state: `%{user_id, follow_ids, saved_recipe_ids}`. `blueprint_match` is
  the optional `?blueprint_slug=` enrichment block (see `BlueprintMatchJSON`),
  omitted when `nil`.
  """
  def feed_card(post, ctx, blueprint_match \\ nil) do
    recipe = post.reference
    author = recipe && recipe.user

    %{
      id: recipe.id,
      title: recipe.title,
      description: recipe.description,
      image_url: recipe.image_url,
      list_image_url: recipe.list_image_url || recipe.image_url,
      author: UserJSON.author(author),
      hashtags: hashtags(recipe),
      servings: recipe.servings,
      prep_time: time_range(recipe.preperation_time_lower_limit, recipe.preperation_time_upper_limit),
      cook_time: time_range(recipe.cooking_time_lower_limit, recipe.cooking_time_upper_limit),
      likes_count: length(post.upvotes || []),
      comments_count: length((recipe.comments) || []),
      liked_by_me: liked_by_me?(post, ctx),
      saved_by_me: saved?(recipe, ctx),
      following_author: following?(author, ctx),
      inserted_at: utc(recipe.inserted_at)
    }
    |> maybe_blueprint_match(blueprint_match)
  end

  @doc """
  Full recipe detail. `engagement` is `Posts.get_recipe_engagement/2`; `ctx`
  carries `%{saved_recipe_ids, follow_ids}`. `blueprint_match` is the optional
  `?blueprint_slug=` enrichment block, omitted when `nil`.
  """
  def detail(recipe, engagement, ctx, blueprint_match \\ nil) do
    %{
      id: recipe.id,
      title: recipe.title,
      description: recipe.description,
      author: UserJSON.author(recipe.user),
      image_url: recipe.image_url,
      detail_image_url: recipe.detail_image_url || recipe.image_url,
      servings: recipe.servings,
      difficulty: recipe.difficulty,
      cousine: recipe.cousine,
      prep_time: time_range(recipe.preperation_time_lower_limit, recipe.preperation_time_upper_limit),
      cook_time: time_range(recipe.cooking_time_lower_limit, recipe.cooking_time_upper_limit),
      private: recipe.private,
      original_url: recipe.original_url,
      hashtags: hashtags(recipe),
      ingredients: Enum.map(recipe.recipe_ingredients || [], &ingredient/1),
      steps: Enum.map(recipe.steps || [], &step/1),
      nutrients: nutrients(recipe.nutrients),
      primary_nutrients_size: recipe.primary_nutrients_size,
      likes_count: engagement.likes_count,
      comments_count: engagement.comments_count,
      liked_by_me: engagement.liked_by_me,
      saved_by_me: saved?(recipe, ctx),
      following_author: following?(recipe.user, ctx)
    }
    |> maybe_blueprint_match(blueprint_match)
    |> data()
  end

  @doc """
  A lightweight card for profile grids (spec §6) — no engagement/post.
  `blueprint_match` is the optional `?blueprint_slug=` enrichment, omitted when `nil`.
  """
  def card(recipe, blueprint_match \\ nil) do
    %{
      id: recipe.id,
      title: recipe.title,
      image_url: recipe.image_url,
      list_image_url: recipe.list_image_url || recipe.image_url,
      servings: recipe.servings
    }
    |> maybe_blueprint_match(blueprint_match)
  end

  # ── parts ────────────────────────────────────────────────────────────────

  defp ingredient(ri) do
    %{
      id: ri.id,
      quantity: ri.quantity,
      ingredient_allias: ri.ingredient_allias,
      measurement_unit_id: ri.measurement_unit_id,
      ingredient_portion_id: ri.ingredient_portion_id,
      measurement_unit: measurement_unit(ri),
      ingredient: base_ingredient(ri.ingredient)
    }
  end

  # A recipe ingredient resolves to one of three unit kinds: a real
  # `MeasurementUnit` (e.g. "piece"), a description-only USDA `IngredientPortion`
  # ("1 medium banana") with no unit, or bare grams. The last two carry a nil
  # `measurement_unit_id`, so serializing the raw association yielded `null` for
  # ~44% of rows. Mirror `RecipeIngredient.unit_label/1` so the client always
  # gets a usable unit name (`id` stays nil when there is no real unit row).
  defp measurement_unit(%RecipeIngredient{measurement_unit: %MeasurementUnit{id: id, name: name}})
       when is_binary(name) do
    %{id: id, name: name, abbreviation: nil}
  end

  defp measurement_unit(%RecipeIngredient{} = ri) do
    %{id: nil, name: RecipeIngredient.unit_label(ri), abbreviation: nil}
  end

  defp base_ingredient(%Ecto.Association.NotLoaded{}), do: nil
  defp base_ingredient(nil), do: nil

  defp base_ingredient(ingredient) do
    %{id: ingredient.id, name: ingredient.name, species_slug: slugify(ingredient.name)}
  end

  defp step(step) do
    %{index: step.index, title: step.title, description: step.description}
  end

  # The stored nutrient tree keeps raw USDA fatty-acid notation at its leaves
  # (e.g. "MUFA 16:1", "PUFA 20:5 n-3 (EPA)"). Resolve those to their canonical
  # common names at read time — same as the web nutrition accordion — so the
  # mobile client shows "Palmitoleic acid (C16:1, Omega-7)" rather than raw codes.
  # Keys are top-level nutrient names ("Total Fat", …); fatty acids live only in
  # the nested children, so the keys are preserved and each value is walked.
  defp nutrients(nil), do: %{}

  defp nutrients(map) when is_map(map) do
    Map.new(map, fn {name, node} -> {name, FattyAcidMatcher.resolve_names(node)} end)
  end

  defp hashtags(recipe) do
    case recipe.recipe_hashtags do
      list when is_list(list) ->
        list |> Enum.map(&(&1.hashtag && &1.hashtag.title)) |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp maybe_blueprint_match(map, nil), do: map
  defp maybe_blueprint_match(map, block), do: Map.put(map, :blueprint_match, block)

  defp time_range(nil, nil), do: nil
  defp time_range(lower, upper), do: %{lower: lower, upper: upper || lower}

  defp liked_by_me?(_post, %{user_id: nil}), do: false

  defp liked_by_me?(post, %{user_id: uid}) do
    case post.upvotes do
      list when is_list(list) -> Enum.any?(list, &(&1.user_id == uid))
      _ -> false
    end
  end

  defp liked_by_me?(_post, _ctx), do: false

  defp saved?(recipe, %{saved_recipe_ids: ids}) when is_list(ids), do: recipe.id in ids
  defp saved?(_recipe, _ctx), do: false

  defp following?(nil, _ctx), do: false
  defp following?(author, %{follow_ids: ids}) when is_list(ids), do: author.id in ids
  defp following?(_author, _ctx), do: false

  defp slugify(nil), do: nil

  defp slugify(name) do
    name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end
end
