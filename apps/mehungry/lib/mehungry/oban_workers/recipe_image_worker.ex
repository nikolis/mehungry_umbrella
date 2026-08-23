defmodule Mehungry.RecipeImageWorker do
  @moduledoc """
  Background job that generates an AI cover image for a recipe (via
  `Mehungry.AI.ImageGenerator`) and stores it in S3, then updates the recipe's
  image_url.

  Triggered from Food.create_recipe/1 when no image_url is provided.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 2

  require Logger

  alias Mehungry.{Food, AI.ImageGenerator}
  alias Mehungry.S3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id}}) do
    recipe = Food.get_recipe!(recipe_id)

    if recipe.image_url not in [nil, ""] do
      Logger.info("RecipeImageWorker: recipe #{recipe_id} already has an image, skipping")
      :ok
    else
      generate_and_store(recipe)
    end
  end

  defp generate_and_store(recipe) do
    case ImageGenerator.generate(recipe.title, recipe.description, cuisine: recipe.cousine) do
      {:ok, binary} ->
        bucket = Application.get_env(:mehungry_web, :aws_bucket)

        key = "recipe_images/#{recipe.id}.jpg"

        case S3.upload_binary(binary, bucket, key, content_type: "image/jpeg") do
          {:ok, _} ->
            url = "https://#{bucket}.s3.eu-central-1.amazonaws.com/#{key}"

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
              "RecipeImageWorker: S3 upload failed for recipe #{recipe.id}: #{inspect(reason)}"
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
