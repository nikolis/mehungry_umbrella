defmodule Mehungry.SocialMediaPublisher do
  @moduledoc """
  Publishes bot recipes to all connected social media platforms.
  Uses the translated title/description when a RecipeTranslation exists for the given language.
  Facebook page and Pinterest board are resolved per-language from the bot config.
  """

  @behaviour Mehungry.SocialMediaPublisherBehaviour

  require Logger

  alias Mehungry.Api.Facebook
  alias Mehungry.Api.Pinterest
  alias Mehungry.{AiBot, Food, Instagram}

  @doc """
  Publishes a recipe to all platforms that have connected tokens on the bot_user.
  Uses the translation for `language_name` when building captions.
  Page and board targets are resolved from bot_config per language.

  Returns %{instagram: result, facebook: result, pinterest: result}
  where result is :ok | :skipped | {:error, reason}.
  """
  @impl true
  def publish_recipe(recipe, bot_user, ai_bot_recipe_id, language_name, opts \\ %{}) do
    localized_recipe = apply_translation(recipe, language_name)
    bot_recipe = AiBot.get_bot_recipe!(ai_bot_recipe_id)
    config = bot_recipe.bot_config
    allowed = opts["platforms"] || opts[:platforms]

    results = %{
      instagram:
        post_platform("instagram", allowed, fn -> post_instagram(bot_user, localized_recipe) end),
      facebook:
        post_platform("facebook", allowed, fn ->
          post_facebook(bot_user, localized_recipe, config, language_name, opts)
        end),
      pinterest:
        post_platform("pinterest", allowed, fn ->
          post_pinterest(bot_user, localized_recipe, config, language_name, opts)
        end)
    }

    log_results(results, ai_bot_recipe_id, language_name)
    Map.new(results, fn {k, {result, _, _}} -> {k, result} end)
  end

  defp post_platform(_platform, nil, fun), do: fun.()

  defp post_platform(platform, allowed, fun) when is_list(allowed) do
    if platform in allowed, do: fun.(), else: {:skipped, nil, nil}
  end

  defp apply_translation(recipe, language_name) do
    recipe = apply_ingredient_translations(recipe, language_name)

    case AiBot.get_recipe_translation(recipe.id, language_name) do
      nil ->
        recipe

      %{title: title, description: description} = translation ->
        recipe
        |> Map.put(:title, title || recipe.title)
        |> Map.put(:description, description || recipe.description)
        |> maybe_apply_translated_steps(translation)
    end
  end

  defp apply_ingredient_translations(recipe, language_name) do
    items = recipe.recipe_ingredients

    ingredient_ids = Enum.map(items, & &1.ingredient_id)
    unit_ids = items |> Enum.map(& &1.measurement_unit_id) |> Enum.uniq()

    ing_names = Food.ingredient_display_names(ingredient_ids, language_name)
    unit_names = Food.get_unit_translations_map(unit_ids, language_name)

    translated_items =
      Enum.map(items, fn ri ->
        ingredient =
          Map.put(ri.ingredient, :name, Map.get(ing_names, ri.ingredient_id, ri.ingredient.name))

        unit =
          Map.put(
            ri.measurement_unit,
            :name,
            Map.get(unit_names, ri.measurement_unit_id, ri.measurement_unit.name)
          )

        ri |> Map.put(:ingredient, ingredient) |> Map.put(:measurement_unit, unit)
      end)

    Map.put(recipe, :recipe_ingredients, translated_items)
  end

  defp maybe_apply_translated_steps(recipe, %{steps: steps})
       when is_list(steps) and steps != [] do
    translated_steps =
      Enum.map(steps, fn step_map ->
        desc = step_map["description"] || step_map[:description] || ""
        idx = step_map["index"] || step_map[:index] || 0
        %{(recipe.steps |> Enum.at(idx) || %{}) | description: desc}
      end)

    Map.put(recipe, :steps, translated_steps)
  end

  defp maybe_apply_translated_steps(recipe, _), do: recipe

  defp post_instagram(bot_user, recipe) do
    user_id = (bot_user.instagram_token || %{}) |> Map.get("user_id", "") |> to_string()

    case Instagram.post_recipe(bot_user, recipe) do
      {:ok, %{media_id: _}} ->
        {:ok, user_id, nil}

      {:error, :not_connected} ->
        {:skipped, nil, nil}

      {:error, :token_stale} ->
        {{:error, "Instagram token expired/invalid — reconnect the account"}, user_id, nil}

      {:error, {:http_error, status, body}} ->
        {{:error, "Instagram HTTP #{status}: #{inspect(body)}"}, user_id, nil}

      {:error, reason} ->
        {{:error, inspect(reason)}, user_id, nil}
    end
  end

  defp post_facebook(bot_user, recipe, config, language_name, opts \\ %{}) do
    if map_non_empty?(bot_user.facebook_token) do
      override_id = nonempty(opts["facebook_page_id"] || opts[:facebook_page_id])

      page =
        if override_id,
          do: find_facebook_page(bot_user, override_id),
          else: resolve_facebook_page(bot_user, config, language_name)

      if is_nil(page) do
        Logger.warning(
          "[SocialMediaPublisher] No Facebook page configured for language #{language_name}"
        )

        {:skipped, nil, nil}
      else
        page_id = Map.get(page, "id")
        page_name = Map.get(page, "name")

        result =
          case Facebook.post_recipe_container(bot_user, recipe, page) do
            {:ok, _response} ->
              :ok

            {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
              :ok

            {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
              {:error, "Facebook HTTP #{status}: #{body}"}

            {:error, reason} ->
              {:error, reason}

            _ ->
              :ok
          end

        {result, page_id, page_name}
      end
    else
      {:skipped, nil, nil}
    end
  end

  defp post_pinterest(bot_user, recipe, config, language_name, opts \\ %{}) do
    if map_non_empty?(bot_user.pinterest_token) do
      board_id =
        nonempty(opts["pinterest_board_id"] || opts[:pinterest_board_id]) ||
          resolve_pinterest_board(config, language_name)

      if board_id do
        result =
          case Pinterest.create_pin(bot_user, recipe, board_id) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {result, board_id, nil}
      else
        Logger.warning(
          "[SocialMediaPublisher] No Pinterest board configured for language #{language_name}"
        )

        {:skipped, nil, nil}
      end
    else
      {:skipped, nil, nil}
    end
  end

  defp find_facebook_page(bot_user, page_id) do
    (bot_user.facebook_token || %{})
    |> Map.values()
    |> Enum.find(fn p -> Map.get(p, "id") == page_id end)
  end

  defp nonempty(nil), do: nil
  defp nonempty(""), do: nil
  defp nonempty(val), do: val

  # Resolve Facebook page: per-language first, then single fallback, then first page.
  defp resolve_facebook_page(bot_user, config, language_name) do
    token_pages = bot_user.facebook_token || %{}

    page_id =
      get_in(config.facebook_page_ids || %{}, [language_name]) ||
        config.facebook_page_id

    if page_id do
      Enum.find(Map.values(token_pages), fn p -> Map.get(p, "id") == page_id end)
    else
      Map.values(token_pages) |> List.first()
    end
  end

  # Resolve Pinterest board: per-language first, then single fallback.
  defp resolve_pinterest_board(config, language_name) do
    get_in(config.pinterest_board_ids || %{}, [language_name]) ||
      config.pinterest_default_board_id
  end

  defp log_results(results, ai_bot_recipe_id, language_name) do
    Enum.each(results, fn {platform, {result, target_id, target_name}} ->
      {status, error} =
        case result do
          :skipped -> {"skipped", nil}
          :ok -> {"ok", nil}
          {:error, reason} -> {"error", to_string(reason)}
        end

      if status == "error" do
        Logger.error(
          "[SocialMediaPublisher] #{platform} publish failed for bot_recipe #{ai_bot_recipe_id} " <>
            "(language #{language_name}, target #{inspect(target_id)}): #{error}"
        )
      end

      posted_at = if status == "ok", do: DateTime.utc_now() |> DateTime.truncate(:second)

      case AiBot.create_post_log(%{
             ai_bot_recipe_id: ai_bot_recipe_id,
             platform: to_string(platform),
             status: status,
             language_name: language_name,
             error: error,
             posted_at: posted_at,
             target_id: target_id,
             target_name: target_name
           }) do
        {:ok, _log} ->
          :ok

        {:error, changeset} ->
          Logger.error(
            "[SocialMediaPublisher] failed to persist post log for #{platform} " <>
              "bot_recipe #{ai_bot_recipe_id} (language #{language_name}): #{inspect(changeset.errors)}"
          )
      end
    end)
  end

  defp map_non_empty?(map) when is_map(map) and map_size(map) > 0, do: true
  defp map_non_empty?(_), do: false
end
