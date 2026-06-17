defmodule Mehungry.ObanWorkers.DailyRecipeGenerationWorker do
  @moduledoc """
  Scheduled daily at 2am UTC.
  Generates 5 AI recipes (one per meal type) for the next day based on the active
  monthly theme config. Schedules individual RecipePublishWorker jobs per (meal, language).
  """

  use Oban.Worker,
    queue: :ai_agents,
    max_attempts: 2,
    unique: [period: 300, fields: [:args]]

  require Logger

  alias Mehungry.{Food, Posts, AiBot, Accounts, Repo}
  alias Mehungry.AI.Agents.RecipeAgent
  alias Mehungry.AiBot.Notifier
  alias Mehungry.ObanWorkers.RecipePublishWorker

  @meal_prompts %{
    "breakfast" => "light and nourishing breakfast recipe — suitable for the morning, could be egg-based, yogurt-based, or grain-based",
    "morning_snack" => "healthy mid-morning snack recipe — light, easy to prepare, energizing",
    "lunch" => "satisfying main lunch recipe — a full meal with vegetables, protein, and grains or legumes",
    "afternoon_snack" => "light afternoon snack recipe — sweet or savory, easy to prepare quickly",
    "dinner" => "hearty dinner recipe — a warming complete evening meal with rich flavors"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    target_date =
      case Map.get(args, "target_date") do
        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> Date.add(Date.utc_today(), 1)
          end

        _ ->
          Date.add(Date.utc_today(), 1)
      end

    month = target_date.month
    year = target_date.year

    case AiBot.get_active_config_for_month(month, year) do
      nil ->
        Logger.info("[DailyRecipeGenerationWorker] No active bot config for #{month}/#{year}, skipping")
        :ok

      config ->
        bot_user = Accounts.get_user!(config.bot_user_id)
        generated = generate_recipes(config, bot_user, target_date)

        broadcast_pending_update()
        if generated > 0, do: notify_admin(generated, target_date)

        :ok
    end
  end

  defp generate_recipes(config, bot_user, target_date) do
    AiBot.AiBotConfig.meal_types()
    |> Task.async_stream(
      fn meal_type ->
        if AiBot.bot_recipe_exists?(config.id, meal_type, target_date) do
          Logger.info("[DailyRecipeGenerationWorker] #{meal_type} for #{target_date} already exists, skipping")
          :skipped
        else
          generate_one(config, bot_user, meal_type, target_date)
        end
      end,
      timeout: 180_000,
      on_timeout: :kill_task,
      max_concurrency: 5
    )
    |> Enum.count(fn
      {:ok, :ok} -> true
      _ -> false
    end)
  end

  defp generate_one(config, bot_user, meal_type, target_date) do
    description = build_description(config.theme, meal_type)
    Logger.info("[DailyRecipeGenerationWorker] Generating #{meal_type} for #{target_date}: #{description}")

    case RecipeAgent.run(description) do
      {:ok, attrs, _} ->
        attrs =
          attrs
          |> Map.put("user_id", bot_user.id)
          |> Map.put("language_name", "en")

        result =
          Repo.transaction(fn ->
            with {:ok, recipe} <- Food.create_recipe(attrs),
                 _ <- Posts.create_post(recipe),
                 {:ok, bot_recipe} <-
                   AiBot.create_bot_recipe(%{
                     recipe_id: recipe.id,
                     bot_config_id: config.id,
                     meal_type: meal_type,
                     scheduled_date: target_date,
                     status: "pending_review"
                   }) do
              schedule_publish_jobs(config, bot_recipe, target_date, meal_type)
            else
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        case result do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("[DailyRecipeGenerationWorker] Failed to persist #{meal_type}: #{inspect(reason)}")
            :error
        end

      {:error, reason} ->
        Logger.error("[DailyRecipeGenerationWorker] RecipeAgent failed for #{meal_type}: #{inspect(reason)}")
        :error
    end
  end

  defp schedule_publish_jobs(config, bot_recipe, target_date, meal_type) do
    lang_times = get_in(config.publish_times, [meal_type]) || %{}

    Enum.each(lang_times, fn {lang, time_str} ->
      case Time.from_iso8601(time_str) do
        {:ok, time} ->
          scheduled_at = DateTime.new!(target_date, time, "Etc/UTC")

          RecipePublishWorker.new(
            %{ai_bot_recipe_id: bot_recipe.id, language_name: lang},
            scheduled_at: scheduled_at
          )
          |> Oban.insert()

        {:error, reason} ->
          Logger.warning("[DailyRecipeGenerationWorker] Invalid time #{time_str} for #{meal_type}/#{lang}: #{inspect(reason)}")
      end
    end)
  end

  defp build_description(theme, meal_type) do
    meal_hint = Map.get(@meal_prompts, meal_type, "recipe")
    "A #{theme} themed #{meal_hint}. The recipe must fit the #{theme} theme in ingredients and style."
  end

  defp broadcast_pending_update do
    count = AiBot.count_pending_reviews()
    Phoenix.PubSub.broadcast(Mehungry.PubSub, "admin:bot_recipes", {:pending_count_updated, count})
  end

  defp notify_admin(recipe_count, target_date) do
    review_url = "https://www.m3hungry.com/professional/ai-bot/review"

    case Notifier.deliver_recipes_ready(recipe_count, review_url) do
      {:ok, _} ->
        Logger.info("[DailyRecipeGenerationWorker] Admin notified: #{recipe_count} recipes for #{target_date}")

      {:error, reason} ->
        Logger.warning("[DailyRecipeGenerationWorker] Failed to send admin notification: #{inspect(reason)}")
    end
  end
end
