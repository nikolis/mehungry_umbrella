defmodule Mehungry.ObanWorkers.RecipePublishWorker do
  @moduledoc """
  Scheduled via `scheduled_at` by DailyRecipeGenerationWorker — one job per (meal_type, language).
  Posts the recipe to all connected social media platforms using the translated caption
  for the given language.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Mehungry.{AiBot, Accounts, Food}

  @all_platforms ["instagram", "facebook", "pinterest"]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"ai_bot_recipe_id" => bot_recipe_id, "language_name" => lang} = args
      }) do
    bot_recipe = AiBot.get_bot_recipe!(bot_recipe_id)

    if bot_recipe.status != "approved" do
      Logger.info(
        "[RecipePublishWorker] bot_recipe #{bot_recipe_id} status=#{bot_recipe.status}, skipping publish"
      )

      :ok
    else
      config = bot_recipe.bot_config
      requested = Map.get(args, "platforms") || @all_platforms

      # Skip platforms that already have an "ok" post log for this
      # recipe+language, so Oban retries after a partial failure never
      # double-post. Manual re-publishes pass "force" to bypass this.
      already_ok =
        if Map.get(args, "force"),
          do: [],
          else: AiBot.platforms_successfully_posted(bot_recipe_id, lang)

      remaining = requested -- already_ok

      if remaining == [] do
        Logger.info(
          "[RecipePublishWorker] bot_recipe #{bot_recipe_id} (#{lang}) already published to #{inspect(requested)}, nothing to do"
        )

        maybe_mark_published(bot_recipe, config)
        :ok
      else
        publish_platforms(bot_recipe, remaining, args, lang)
      end
    end
  end

  defp publish_platforms(bot_recipe, platforms, args, lang) do
    config = bot_recipe.bot_config
    bot_user = Accounts.get_user!(config.bot_user_id)

    recipe =
      Food.get_recipe_no_caching!(bot_recipe.recipe_id)
      |> Mehungry.Repo.preload([
        :user,
        recipe_ingredients: [:ingredient, :measurement_unit],
        recipe_hashtags: []
      ])

    opts = %{
      "platforms" => platforms,
      "facebook_page_id" => Map.get(args, "facebook_page_id"),
      "pinterest_board_id" => Map.get(args, "pinterest_board_id")
    }

    results = publisher().publish_recipe(recipe, bot_user, bot_recipe.id, lang, opts)

    log_outcome(results, bot_recipe.id, lang)
    maybe_mark_published(bot_recipe, config)

    case collect_errors(results) do
      [] ->
        :ok

      errors ->
        {:error, "publish failures — " <> Enum.join(errors, "; ")}
    end
  end

  defp publisher do
    Application.get_env(:mehungry, :social_media_publisher, Mehungry.Social.Publisher)
  end

  defp collect_errors(results) when is_map(results) do
    for {platform, {:error, reason}} <- results, do: "#{platform}: #{inspect(reason)}"
  end

  defp collect_errors(_results), do: []

  # Surface the per-platform outcome in the app log so production/network
  # failures are visible without querying social_media_post_logs.
  defp log_outcome(results, bot_recipe_id, lang) when is_map(results) do
    errored =
      for {platform, {:error, reason}} <- results,
          do: "#{platform}: #{inspect(reason)}"

    if errored == [] do
      Logger.info(
        "[RecipePublishWorker] bot_recipe #{bot_recipe_id} (#{lang}) publish outcome: #{inspect(results)}"
      )
    else
      Logger.error(
        "[RecipePublishWorker] bot_recipe #{bot_recipe_id} (#{lang}) had publish failures — " <>
          Enum.join(errored, "; ")
      )
    end
  end

  defp log_outcome(results, bot_recipe_id, lang) do
    Logger.warning(
      "[RecipePublishWorker] bot_recipe #{bot_recipe_id} (#{lang}) publisher returned unexpected result: #{inspect(results)}"
    )
  end

  defp maybe_mark_published(bot_recipe, config) do
    languages = Map.keys(get_in(config.publish_times, [bot_recipe.meal_type]) || %{})

    if AiBot.all_languages_published?(bot_recipe.id, languages) do
      AiBot.mark_published(bot_recipe)
    end
  end
end
