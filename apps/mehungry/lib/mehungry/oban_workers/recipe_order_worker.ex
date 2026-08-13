defmodule Mehungry.ObanWorkers.RecipeOrderWorker do
  @moduledoc """
  Fulfils an ad-hoc `AI.Bot.RecipeOrder`: generates `quantity` recipes for the
  order's `RecipeSetup` (persona + origin + story + seed ingredients + optional
  condition) and lands them in the review queue as `pending_review`, tagged to
  the order. No publish scheduling — publishing is manual from the review queue.

  Decoupled from the monthly calendar: order recipes carry `bot_config_id: nil`
  and `scheduled_date: today` so they slot into the existing review UI.
  """

  use Oban.Worker,
    queue: :ai_agents,
    max_attempts: 2,
    unique: [period: 300, fields: [:args]]

  require Logger

  alias Mehungry.{Food, Accounts, Repo}
  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.AiBotConfig
  alias Mehungry.AI.Agents.RecipeAgent
  alias Mehungry.AI.Bot.Notifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Bot.get_recipe_order!(order_id)

    case order.status do
      "completed" ->
        Logger.info("[RecipeOrderWorker] Order #{order_id} already completed, skipping")
        :ok

      _ ->
        run_order(order)
    end
  end

  defp run_order(order) do
    Bot.update_recipe_order(order, %{status: "generating"})

    bot_user = Accounts.get_user!(order.bot_user_id)
    setup = order.recipe_setup
    brief_opts = Bot.build_brief(setup) || []
    avoid_ids = setup_avoid_ids(setup)
    meal_types = meal_type_sequence(order)

    generated =
      meal_types
      |> Enum.with_index()
      |> Task.async_stream(
        fn {meal_type, _idx} ->
          description = order_description(setup, meal_type)
          generate_one(order, bot_user, meal_type, description, brief_opts, avoid_ids)
        end,
        timeout: 180_000,
        on_timeout: :kill_task,
        max_concurrency: 2
      )
      |> Enum.count(fn
        {:ok, :ok} -> true
        _ -> false
      end)

    final_status = if generated > 0, do: "completed", else: "failed"
    Bot.update_recipe_order(order, %{status: final_status})

    broadcast_pending_update()
    if generated > 0, do: notify_admin(generated)

    Logger.info(
      "[RecipeOrderWorker] Order #{order.id}: generated #{generated}/#{order.quantity} recipes (#{final_status})"
    )

    :ok
  end

  defp generate_one(order, bot_user, meal_type, description, brief_opts, avoid_ids) do
    case generate_attrs(description, brief_opts, avoid_ids) do
      {:ok, attrs} ->
        attrs = attrs |> Map.put("user_id", bot_user.id) |> Map.put("language_name", "En")
        persist(order, meal_type, attrs)

      {:error, reason} ->
        Logger.error("[RecipeOrderWorker] Recipe generation failed: #{inspect(reason)}")
        :error
    end
  end

  defp persist(order, meal_type, attrs) do
    result =
      Repo.transaction(fn ->
        with {:ok, recipe} <- Food.create_recipe(attrs),
             _ <- Mehungry.Posts.create_post(recipe),
             {:ok, _bot_recipe} <-
               Bot.create_bot_recipe(%{
                 recipe_id: recipe.id,
                 recipe_order_id: order.id,
                 meal_type: meal_type,
                 scheduled_date: Date.utc_today(),
                 status: "pending_review"
               }) do
          :ok
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, _} ->
        Bot.increment_order_completed(order)
        :ok

      {:error, reason} ->
        Logger.error("[RecipeOrderWorker] Failed to persist recipe: #{inspect(reason)}")
        :error
    end
  end

  # Same hard-exclude guard as the daily worker: retry when the recipe carries a
  # seed "avoid" ingredient.
  @max_attempts 3

  defp generate_attrs(description, brief_opts, avoid_ids) do
    if MapSet.size(avoid_ids) > 0 do
      generate_avoiding(description, brief_opts, avoid_ids, @max_attempts)
    else
      case RecipeAgent.run(description, brief_opts) do
        {:ok, attrs, _} -> {:ok, attrs}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp generate_avoiding(_description, _brief_opts, _avoid_ids, 0) do
    {:error, "could not generate a recipe free of avoided ingredients"}
  end

  defp generate_avoiding(description, brief_opts, avoid_ids, attempts_left) do
    case RecipeAgent.run(description, brief_opts) do
      {:ok, attrs, _} ->
        offending =
          (attrs["recipe_ingredients"] || [])
          |> Enum.map(fn ri -> ri["ingredient_id"] || ri[:ingredient_id] end)
          |> Enum.filter(&MapSet.member?(avoid_ids, &1))

        if offending == [] do
          {:ok, attrs}
        else
          generate_avoiding(description, brief_opts, avoid_ids, attempts_left - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A nil order meal_type cycles across all meal types; a set one repeats.
  defp meal_type_sequence(order) do
    meal_types = AiBotConfig.meal_types()

    case order.meal_type do
      nil ->
        Enum.map(0..(order.quantity - 1), fn i ->
          Enum.at(meal_types, rem(i, length(meal_types)))
        end)

      meal_type ->
        List.duplicate(meal_type, order.quantity)
    end
  end

  defp setup_avoid_ids(nil), do: MapSet.new()

  defp setup_avoid_ids(setup) do
    (setup.seed_ingredients || [])
    |> Enum.filter(&(&1.role == "avoid"))
    |> Enum.map(& &1.ingredient_id)
    |> MapSet.new()
  end

  # Meal-type hints so the agent always has a concrete dish class to anchor on —
  # a too-vague prompt makes it flail without ever submitting a recipe. Mirrors
  # DailyRecipeGenerationWorker's @meal_prompts.
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

  # The persona/origin/story steering comes through brief_opts, and any
  # condition's benefit is carried concretely by the setup's encouraged
  # (primary) and avoided seed ingredients — NOT by asking the model to reason
  # about the disease. So this description only names the dish class and the
  # culinary diet direction (e.g. "Mediterranean diet"), never the condition.
  defp order_description(setup, meal_type) do
    meal_hint = Map.get(@meal_prompts, meal_type, "recipe")

    case setup && setup.diet_direction do
      direction when is_binary(direction) and direction != "" -> "A #{direction} #{meal_hint}."
      _ -> "A #{meal_hint}."
    end
  end

  defp broadcast_pending_update do
    count = Bot.count_pending_reviews()

    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      "admin:bot_recipes",
      {:pending_count_updated, count}
    )
  end

  defp notify_admin(recipe_count) do
    review_url = "https://www.m3hungry.com/professional/ai-bot/review"

    case Notifier.deliver_recipes_ready(recipe_count, review_url) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("[RecipeOrderWorker] Notify failed: #{inspect(reason)}")
    end
  end
end
