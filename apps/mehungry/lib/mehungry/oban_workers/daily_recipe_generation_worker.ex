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

  alias Mehungry.{Food, Health, Posts, Accounts, Repo}
  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.RecipeGeneration
  alias Mehungry.AI.Bot.Notifier
  alias Mehungry.ObanWorkers.RecipePublishWorker

  # How many times to re-ask the agent when a condition-setup recipe comes back
  # carrying a discouraged ingredient before giving up on that meal.
  @max_condition_attempts 3

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

    case resolve_config(args, target_date) do
      nil ->
        Logger.info(
          "[DailyRecipeGenerationWorker] No bot config to generate for (target #{target_date}), skipping"
        )

        :ok

      config ->
        bot_user = Accounts.get_user!(config.bot_user_id)
        generated = generate_recipes(config, bot_user, target_date)

        broadcast_pending_update()
        if generated > 0, do: notify_admin(generated, target_date)

        :ok
    end
  end

  # An admin-triggered "Generate now" passes an explicit `bot_config_id` (chosen
  # in the review queue), so we generate against that exact config regardless of
  # its month. The scheduled 2am cron run passes no id and falls back to the
  # active config for the target date's month.
  defp resolve_config(args, target_date) do
    case Map.get(args, "bot_config_id") do
      id when is_integer(id) or (is_binary(id) and id != "") ->
        Bot.get_bot_config!(id)

      _ ->
        Bot.get_active_config_for_month(target_date.month, target_date.year)
    end
  end

  defp generate_recipes(config, bot_user, target_date) do
    Bot.AiBotConfig.meal_types()
    |> Task.async_stream(
      fn meal_type ->
        if Bot.bot_recipe_exists?(config.id, meal_type, target_date) do
          Logger.info(
            "[DailyRecipeGenerationWorker] #{meal_type} for #{target_date} already exists, skipping"
          )

          :skipped
        else
          generate_one(config, bot_user, meal_type, target_date)
        end
      end,
      timeout: 180_000,
      on_timeout: :kill_task,
      max_concurrency: 2
    )
    |> Enum.count(fn
      {:ok, :ok} -> true
      _ -> false
    end)
  end

  defp generate_one(config, bot_user, meal_type, target_date) do
    case resolve_recipe_attrs(config, meal_type, target_date) do
      {:ok, attrs} ->
        attrs =
          attrs
          |> Map.put("user_id", bot_user.id)
          |> Map.put("language_name", "En")

        result =
          Repo.transaction(fn ->
            with {:ok, recipe} <- Food.create_recipe(attrs),
                 _ <- Posts.create_post(recipe),
                 {:ok, bot_recipe} <-
                   Bot.create_bot_recipe(%{
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
            Logger.error(
              "[DailyRecipeGenerationWorker] Failed to persist #{meal_type}: #{inspect(reason)}"
            )

            :error
        end

      {:error, reason} ->
        Logger.error(
          "[DailyRecipeGenerationWorker] Recipe generation failed for #{meal_type}: #{inspect(reason)}"
        )

        :error
    end
  end

  # Resolve the recipe attrs for a meal, branching on the config's setup type.
  # Condition setups derive encouraged/discouraged ingredients from the linked
  # health condition and hard-reject any recipe that includes a discouraged one.
  defp resolve_recipe_attrs(
         %{setup_type: "condition", condition_id: condition_id} = config,
         meal_type,
         target_date
       )
       when not is_nil(condition_id) do
    %{encouraged: encouraged, discouraged: discouraged} =
      Health.ingredient_guidance_for_condition(condition_id)

    if encouraged == [] and discouraged == [] do
      Logger.warning(
        "[DailyRecipeGenerationWorker] Condition ##{condition_id} yielded no encouraged or " <>
          "discouraged ingredients (no compounds wired to curated species) — the condition " <>
          "will have no effect on this #{meal_type} generation."
      )
    end

    context = Bot.get_context_for_date(config, target_date)
    brief_opts = Bot.build_brief(context.setup) || []
    cuisine = Bot.setup_cuisine(context.setup)

    discouraged_ids =
      MapSet.union(MapSet.new(discouraged, & &1.id), RecipeGeneration.setup_avoid_ids(context.setup))

    description =
      with_cuisine(cuisine, build_condition_description(config, context, meal_type, encouraged, discouraged))

    Logger.info(
      "[DailyRecipeGenerationWorker] Generating #{meal_type} for #{target_date} (condition setup): #{description}"
    )

    RecipeGeneration.generate(description, discouraged_ids, brief_opts,
      attempts: @max_condition_attempts,
      label: meal_type
    )
    |> put_recipe_cuisine(cuisine)
  end

  defp resolve_recipe_attrs(config, meal_type, target_date) do
    context = Bot.get_context_for_date(config, target_date)
    brief_opts = Bot.build_brief(context.setup) || []
    cuisine = Bot.setup_cuisine(context.setup)
    avoid_ids = RecipeGeneration.setup_avoid_ids(context.setup)
    avoid_names = RecipeGeneration.setup_avoid_names(context.setup)
    description = with_cuisine(cuisine, build_description(context, meal_type))

    Logger.info(
      "[DailyRecipeGenerationWorker] Generating #{meal_type} for #{target_date}: #{description}"
    )

    RecipeGeneration.generate(description, avoid_ids, brief_opts,
      attempts: @max_condition_attempts,
      avoid_names: avoid_names,
      label: meal_type
    )
    |> put_recipe_cuisine(cuisine)
  end

  # Lead the description with the cuisine when we have one, and stamp the resolved
  # cuisine onto the recipe attrs (the `cousine` column) so the cover-image worker
  # can style the photo per cuisine instead of the old one-size warm/rustic look.
  defp with_cuisine(nil, description), do: description
  defp with_cuisine(cuisine, description), do: "Cuisine: #{cuisine}. " <> description

  defp put_recipe_cuisine({:ok, attrs}, cuisine) when is_binary(cuisine),
    do: {:ok, Map.put(attrs, "cousine", cuisine)}

  defp put_recipe_cuisine(result, _cuisine), do: result

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
          Logger.warning(
            "[DailyRecipeGenerationWorker] Invalid time #{time_str} for #{meal_type}/#{lang}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp build_description(%{month_theme: mt, week_theme: wt, day_focus: df}, meal_type) do
    meal_hint = RecipeGeneration.meal_prompt(meal_type)
    base = "A #{mt} themed #{meal_hint}"
    base = if wt, do: base <> ", following the '#{wt}' week theme", else: base
    base = if df, do: base <> ", with today's focus: #{df}", else: base
    base <> ". The recipe must fit the #{mt} style in ingredients and spirit."
  end

  defp build_condition_description(config, context, meal_type, encouraged, discouraged) do
    meal_hint = RecipeGeneration.meal_prompt(meal_type)
    encouraged_names = RecipeGeneration.encouraged_names(encouraged)
    discouraged_names = RecipeGeneration.ingredient_names(discouraged)

    # The condition's benefit is carried concretely by the encouraged/avoided
    # ingredient lists — never by asking the model to be "beneficial for a
    # disease". So the base names only the dish class + culinary direction.
    base =
      "A #{config.diet_direction} #{meal_hint}."
      |> RecipeGeneration.append_guidance(encouraged_names, discouraged_names)

    base =
      if context.week_theme,
        do: base <> " Follow the '#{context.week_theme}' week theme.",
        else: base

    if context.day_focus, do: base <> " Today's focus: #{context.day_focus}.", else: base
  end

  defp broadcast_pending_update do
    count = Bot.count_pending_reviews()

    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      "admin:bot_recipes",
      {:pending_count_updated, count}
    )
  end

  defp notify_admin(recipe_count, target_date) do
    review_url = "https://www.m3hungry.com/professional/ai-bot/review"

    case Notifier.deliver_recipes_ready(recipe_count, review_url) do
      {:ok, _} ->
        Logger.info(
          "[DailyRecipeGenerationWorker] Admin notified: #{recipe_count} recipes for #{target_date}"
        )

      {:error, reason} ->
        Logger.warning(
          "[DailyRecipeGenerationWorker] Failed to send admin notification: #{inspect(reason)}"
        )
    end
  end
end
