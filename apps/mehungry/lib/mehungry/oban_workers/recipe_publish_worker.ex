defmodule Mehungry.ObanWorkers.RecipePublishWorker do
  @moduledoc """
  Scheduled via `scheduled_at` by DailyRecipeGenerationWorker — one job per (meal_type, language).
  Posts the recipe to all connected social media platforms using the translated caption
  for the given language.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Mehungry.{AiBot, Accounts, Food}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ai_bot_recipe_id" => bot_recipe_id, "language_name" => lang}}) do
    bot_recipe = AiBot.get_bot_recipe!(bot_recipe_id)

    if bot_recipe.status != "approved" do
      Logger.info("[RecipePublishWorker] bot_recipe #{bot_recipe_id} status=#{bot_recipe.status}, skipping publish")
      :ok
    else
      config = bot_recipe.bot_config
      bot_user = Accounts.get_user!(config.bot_user_id)

      recipe =
        Food.get_recipe_no_caching!(bot_recipe.recipe_id)
        |> Mehungry.Repo.preload([
          :user,
          recipe_ingredients: [:ingredient, :measurement_unit],
          recipe_hashtags: []
        ])

      publisher = Application.get_env(:mehungry, :social_media_publisher, MehungryWeb.SocialMediaPublisher)
      apply(publisher, :publish_recipe, [recipe, bot_user, bot_recipe_id, lang])

      maybe_mark_published(bot_recipe, config)

      :ok
    end
  end

  defp maybe_mark_published(bot_recipe, config) do
    languages = Map.keys(get_in(config.publish_times, [bot_recipe.meal_type]) || %{})

    if AiBot.all_languages_published?(bot_recipe.id, languages) do
      AiBot.mark_published(bot_recipe)
    end
  end
end
