defmodule MehungryWeb.RecipeSocialGraphicWorker do
  @moduledoc """
  Generates a recipe's shareable insight graphic off the request path.

  Lives in the web app (not `apps/mehungry`) because it orchestrates the web-only
  renderer `MehungryWeb.InsightGraphic`; everything else it touches is a core
  facade call. Runs on the shared `:ai_agents` queue like `RecipeImageWorker`.

  Pipeline: rank insight candidates (`AI.RecipeInsight`) → AI headline/caption
  (`AI.InsightCaptioner`, with a deterministic fallback) → render the composite
  (`InsightGraphic`) → upload (`Storage`) → persist a `RecipeSocialGraphic` row →
  meter the `"graphic_generation"` quota → PubSub the result so the triggering
  LiveView swaps its spinner for the finished card.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 2

  alias MehungryWeb.InsightGraphicGenerator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id} = args}) do
    result = InsightGraphicGenerator.generate(recipe_id, args["user_id"])
    broadcast(recipe_id, result)

    case result do
      {:ok, _graphic} -> :ok
      {:error, _reason} = err -> err
    end
  end

  @doc "PubSub topic a LiveView subscribes to for a recipe's graphic result."
  def topic(recipe_id), do: "recipe_social_graphic:#{recipe_id}"

  defp broadcast(recipe_id, result) do
    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      topic(recipe_id),
      {:recipe_social_graphic, recipe_id, result}
    )
  end
end
