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
  alias Mehungry.AI.Agents.RecipeAgent
  alias Mehungry.AI.Bot.Notifier
  alias Mehungry.ObanWorkers.RecipePublishWorker

  # How many times to re-ask the agent when a condition-setup recipe comes back
  # carrying a discouraged ingredient before giving up on that meal.
  @max_condition_attempts 3

  @meal_prompts %{
    "breakfast" =>
      "light and nourishing breakfast recipe — suitable for the morning, could be egg-based, yogurt-based, or grain-based",
    "morning_snack" => "healthy mid-morning snack recipe — light, easy to prepare, energizing",
    "lunch" =>
      "satisfying main lunch recipe — a full meal with vegetables, protein, and grains or legumes",
    "afternoon_snack" =>
      "light afternoon snack recipe — sweet or savory, easy to prepare quickly",
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

    discouraged_ids = MapSet.new(discouraged, & &1.id)
    context = Bot.get_context_for_date(config, target_date)
    description = build_condition_description(config, context, meal_type, encouraged, discouraged)

    Logger.info(
      "[DailyRecipeGenerationWorker] Generating #{meal_type} for #{target_date} (condition setup): #{description}"
    )

    generate_avoiding(description, discouraged_ids, meal_type, @max_condition_attempts)
  end

  defp resolve_recipe_attrs(config, meal_type, target_date) do
    context = Bot.get_context_for_date(config, target_date)
    description = build_description(context, meal_type)

    Logger.info(
      "[DailyRecipeGenerationWorker] Generating #{meal_type} for #{target_date}: #{description}"
    )

    case RecipeAgent.run(description) do
      {:ok, attrs, _} -> {:ok, attrs}
      {:error, reason} -> {:error, reason}
    end
  end

  # Run the agent, rejecting and retrying any recipe that contains a discouraged
  # ingredient. The prompt asks the agent to avoid them; this is the hard guard.
  defp generate_avoiding(_description, _discouraged_ids, meal_type, 0) do
    {:error, "#{meal_type}: could not generate a recipe free of discouraged ingredients"}
  end

  defp generate_avoiding(description, discouraged_ids, meal_type, attempts_left) do
    case RecipeAgent.run(description) do
      {:ok, attrs, _} ->
        case offending_ingredient_ids(attrs, discouraged_ids) do
          [] ->
            {:ok, attrs}

          offending ->
            Logger.warning(
              "[DailyRecipeGenerationWorker] #{meal_type} recipe contained discouraged " <>
                "ingredient_ids #{inspect(offending)}, retrying (#{attempts_left - 1} left)"
            )

            generate_avoiding(description, discouraged_ids, meal_type, attempts_left - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp offending_ingredient_ids(attrs, discouraged_ids) do
    (attrs["recipe_ingredients"] || [])
    |> Enum.map(fn ri -> ri["ingredient_id"] || ri[:ingredient_id] end)
    |> Enum.filter(&MapSet.member?(discouraged_ids, &1))
    |> Enum.uniq()
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
          Logger.warning(
            "[DailyRecipeGenerationWorker] Invalid time #{time_str} for #{meal_type}/#{lang}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp build_description(%{month_theme: mt, week_theme: wt, day_focus: df}, meal_type) do
    meal_hint = Map.get(@meal_prompts, meal_type, "recipe")
    base = "A #{mt} themed #{meal_hint}"
    base = if wt, do: base <> ", following the '#{wt}' week theme", else: base
    base = if df, do: base <> ", with today's focus: #{df}", else: base
    base <> ". The recipe must fit the #{mt} style in ingredients and spirit."
  end

  # Cap the ingredient lists injected into the prompt so it stays bounded; the
  # full discouraged set is still enforced by the post-generation id check.
  @ingredient_name_limit 50

  defp build_condition_description(config, context, meal_type, encouraged, discouraged) do
    meal_hint = Map.get(@meal_prompts, meal_type, "recipe")
    condition_name = (config.condition && config.condition.name) || "the selected health condition"
    encouraged_names = ingredient_names(encouraged)
    discouraged_names = ingredient_names(discouraged)

    base =
      "A #{config.diet_direction} #{meal_hint}, designed to be suitable and beneficial " <>
        "for people with #{condition_name}."

    base =
      if encouraged_names != "",
        do:
          base <>
            " Build the recipe around these encouraged ingredients wherever they fit naturally: " <>
            "#{encouraged_names}.",
        else: base

    base =
      if discouraged_names != "",
        do:
          base <>
            " The recipe MUST NOT contain any of these ingredients under any circumstance: " <>
            "#{discouraged_names}.",
        else: base

    base =
      if context.week_theme,
        do: base <> " Follow the '#{context.week_theme}' week theme.",
        else: base

    base = if context.day_focus, do: base <> " Today's focus: #{context.day_focus}.", else: base
    base
  end

  defp ingredient_names(ingredients) do
    ingredients
    |> Enum.map(& &1.name)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.take(@ingredient_name_limit)
    |> Enum.join(", ")
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
