defmodule MehungryWeb.SocialMediaPublisher do
  @moduledoc """
  Publishes bot recipes to all connected social media platforms.
  Uses the translated title/description when a RecipeTranslation exists for the given language.
  """

  require Logger

  alias Mehungry.Api.Instagram
  alias Mehungry.Api.Facebook
  alias Mehungry.Api.Pinterest
  alias Mehungry.AiBot

  @doc """
  Publishes a recipe to all platforms that have connected tokens on the bot_user.
  Uses the translation for `language_name` when building captions.

  Returns %{instagram: result, facebook: result, pinterest: result}
  where result is :ok | :skipped | {:error, reason}.
  """
  def publish_recipe(recipe, bot_user, ai_bot_recipe_id, language_name) do
    localized_recipe = apply_translation(recipe, language_name)

    results = %{
      instagram: post_instagram(bot_user, localized_recipe),
      facebook: post_facebook(bot_user, localized_recipe),
      pinterest: post_pinterest(bot_user, localized_recipe, ai_bot_recipe_id)
    }

    log_results(results, ai_bot_recipe_id, language_name)
    results
  end

  defp apply_translation(recipe, language_name) do
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

  defp maybe_apply_translated_steps(recipe, %{steps: steps}) when is_list(steps) and steps != [] do
    translated_steps =
      Enum.map(steps, fn step_map ->
        desc = step_map["description"] || step_map[:description] || ""
        idx = step_map["index"] || step_map[:index] || 0
        %{recipe.steps |> Enum.at(idx) || %{} | description: desc}
      end)

    Map.put(recipe, :steps, translated_steps)
  end

  defp maybe_apply_translated_steps(recipe, _), do: recipe

  defp post_instagram(bot_user, recipe) do
    if map_non_empty?(bot_user.instagram_token) do
      case Instagram.post_recipe_container(bot_user, recipe) do
        {:ok, _} -> :ok
        nil -> {:error, "Instagram returned nil"}
        {:error, reason} -> {:error, reason}
        _ -> :ok
      end
    else
      :skipped
    end
  end

  defp post_facebook(bot_user, recipe) do
    if map_non_empty?(bot_user.facebook_token) do
      page = bot_user.facebook_token |> Map.values() |> List.first()

      case Facebook.post_recipe_container(bot_user, recipe, page) do
        {:ok, _response} -> :ok
        {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 -> :ok
        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          {:error, "Facebook HTTP #{status}: #{body}"}
        {:error, reason} -> {:error, reason}
        _ -> :ok
      end
    else
      :skipped
    end
  end

  defp post_pinterest(bot_user, recipe, ai_bot_recipe_id) do
    if map_non_empty?(bot_user.pinterest_token) do
      board_id = get_pinterest_board_id(ai_bot_recipe_id)

      if board_id do
        case Pinterest.create_pin(bot_user, recipe, board_id) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      else
        Logger.warning("[SocialMediaPublisher] No Pinterest board configured for bot_recipe #{ai_bot_recipe_id}")
        :skipped
      end
    else
      :skipped
    end
  end

  defp get_pinterest_board_id(ai_bot_recipe_id) do
    bot_recipe = AiBot.get_bot_recipe!(ai_bot_recipe_id)
    bot_recipe.bot_config.pinterest_default_board_id
  end

  defp log_results(results, ai_bot_recipe_id, language_name) do
    Enum.each(results, fn {platform, result} ->
      {status, error} =
        case result do
          :skipped -> {"skipped", nil}
          :ok -> {"ok", nil}
          {:error, reason} -> {"error", to_string(reason)}
        end

      posted_at = if status == "ok", do: DateTime.utc_now() |> DateTime.truncate(:second)

      AiBot.create_post_log(%{
        ai_bot_recipe_id: ai_bot_recipe_id,
        platform: to_string(platform),
        status: status,
        language_name: language_name,
        error: error,
        posted_at: posted_at
      })
    end)
  end

  defp map_non_empty?(map) when is_map(map) and map_size(map) > 0, do: true
  defp map_non_empty?(_), do: false
end
