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
  alias Mehungry.AI.Bot.RecipeGeneration
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
    cuisine = Bot.setup_cuisine(setup)
    meal_types = meal_type_sequence(order)

    # Live condition guidance resolved from the setup's linked health condition at
    # generation time — the same source the daily worker uses. Encouraged names
    # steer the prompt; discouraged ids join the hard avoid-guard alongside any
    # "avoid" seed ingredients. This makes the condition take effect even when the
    # setup was never "populated from condition" into seed ingredients.
    %{encouraged: encouraged, discouraged: discouraged} =
      RecipeGeneration.condition_guidance(setup)

    encouraged_names = RecipeGeneration.encouraged_names(encouraged)
    discouraged_names = RecipeGeneration.ingredient_names(discouraged)

    avoid_ids =
      MapSet.union(RecipeGeneration.setup_avoid_ids(setup), MapSet.new(discouraged, & &1.id))

    avoid_names =
      Map.merge(RecipeGeneration.setup_avoid_names(setup), Map.new(discouraged, &{&1.id, &1.name}))

    Logger.debug("""
    [RecipeOrderWorker] Starting order ##{order.id} (#{order.quantity} recipe(s))
      setup:       #{(setup && setup.name) || "—"}
      persona:     #{(setup && setup.persona && setup.persona.name) || "none"}
      condition:   #{(setup && setup.condition && setup.condition.name) || "none"}
      encouraged:  #{length(encouraged)}
      avoid ids:   #{MapSet.size(avoid_ids)}
      meal seq:    #{Enum.join(meal_types, ", ")}
    """)

    if setup && setup.condition_id && encouraged == [] and discouraged == [] do
      Logger.warning(
        "[RecipeOrderWorker] Order ##{order.id}: setup '#{setup.name}' is linked to a " <>
          "condition but it yields no encouraged or discouraged ingredients (no compounds " <>
          "wired to curated species) — the condition will have no effect on generation."
      )
    end

    generated =
      meal_types
      |> Enum.with_index()
      |> Task.async_stream(
        fn {meal_type, _idx} ->
          description =
            cuisine
            |> with_cuisine(order_description(setup, meal_type, encouraged_names, discouraged_names))

          generate_one(order, bot_user, meal_type, description, brief_opts, avoid_ids, avoid_names, cuisine)
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

  defp generate_one(order, bot_user, meal_type, description, brief_opts, avoid_ids, avoid_names, cuisine) do
    result =
      RecipeGeneration.generate(description, avoid_ids, brief_opts,
        avoid_names: avoid_names,
        label: meal_type
      )

    case result do
      {:ok, attrs} ->
        attrs =
          attrs
          |> Map.put("user_id", bot_user.id)
          |> Map.put("language_name", "En")
          |> maybe_put_cuisine(cuisine)

        persist(order, meal_type, attrs)

      {:error, reason} ->
        Logger.error("[RecipeOrderWorker] Recipe generation failed: #{inspect(reason)}")
        :error
    end
  end

  # Stamp the resolved cuisine onto the recipe (the `cousine` column) so the cover
  # image is styled per cuisine. Lead the description with it too.
  defp with_cuisine(nil, description), do: description
  defp with_cuisine(cuisine, description), do: "Cuisine: #{cuisine}. " <> description

  defp maybe_put_cuisine(attrs, cuisine) when is_binary(cuisine),
    do: Map.put(attrs, "cousine", cuisine)

  defp maybe_put_cuisine(attrs, _cuisine), do: attrs

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

  # The persona/origin/story steering comes through brief_opts. A condition's
  # benefit is carried concretely by its encouraged/discouraged ingredient
  # names — NOT by asking the model to reason about the disease. So the
  # description names the dish class, the culinary diet direction (e.g.
  # "Mediterranean diet"), and those ingredient lists, but never the condition.
  defp order_description(setup, meal_type, encouraged_names, discouraged_names) do
    meal_hint = RecipeGeneration.meal_prompt(meal_type)

    base =
      case setup && setup.diet_direction do
        direction when is_binary(direction) and direction != "" -> "A #{direction} #{meal_hint}."
        _ -> "A #{meal_hint}."
      end

    RecipeGeneration.append_guidance(base, encouraged_names, discouraged_names)
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
