defmodule Mehungry.RecipeImageWorker do
  @moduledoc """
  Background job that generates an AI cover image for a recipe (via
  `Mehungry.AI.ImageGenerator`) and stores it in S3, then updates the recipe's
  image_url.

  Triggered from Food.create_recipe/1 when no image_url is provided.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 2

  require Logger

  alias Mehungry.{Food, AI.ImageGenerator, Storage}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id} = args}) do
    recipe = Food.get_recipe!(recipe_id)
    force = Map.get(args, "force", false)

    if not force and recipe.image_url not in [nil, ""] do
      Logger.info("RecipeImageWorker: recipe #{recipe_id} already has an image, skipping")
      :ok
    else
      generate_and_store(recipe)
    end
  end

  defp generate_and_store(recipe) do
    case ImageGenerator.generate(recipe.title, recipe.description,
           cuisine: recipe.cousine,
           quality: "high"
         ) do
      {:ok, binary} ->
        key = "recipe_images/#{recipe.id}.jpg"

        case Storage.put(key, binary, content_type: "image/jpeg") do
          {:ok, %{url: url}} ->
            case Food.update_recipe(recipe, %{"image_url" => url}) do
              {:ok, _} ->
                Logger.info("RecipeImageWorker: image saved for recipe #{recipe.id}")
                :ok

              {:error, reason} ->
                Logger.warning(
                  "RecipeImageWorker: failed to update recipe #{recipe.id}: #{inspect(reason)}"
                )

                {:error, reason}
            end

          {:error, reason} ->
            Logger.warning(
              "RecipeImageWorker: storage upload failed for recipe #{recipe.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning(
          "RecipeImageWorker: image generation failed for recipe #{recipe.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
