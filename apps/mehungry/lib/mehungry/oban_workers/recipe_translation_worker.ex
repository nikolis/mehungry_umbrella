defmodule Mehungry.ObanWorkers.RecipeTranslationWorker do
  @moduledoc """
  Translates a recipe's title, description, and steps into the target language
  using the AI RecipeTranslator and stores the result in recipe_translations.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 3

  require Logger

  alias Mehungry.{Food, AiBot}
  alias Mehungry.AI.RecipeTranslator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id, "language_name" => lang}}) do
    recipe = Food.get_recipe_no_caching!(recipe_id)

    Logger.info("[RecipeTranslationWorker] Translating recipe #{recipe_id} to #{lang}")

    case RecipeTranslator.translate_recipe(recipe, lang) do
      {:ok, %{title: title, description: description, steps: steps}} ->
        result =
          AiBot.upsert_recipe_translation(%{
            recipe_id: recipe_id,
            language_name: lang,
            title: title,
            description: description,
            steps: steps
          })

        case result do
          {:ok, _} ->
            Logger.info("[RecipeTranslationWorker] Translated recipe #{recipe_id} to #{lang}")
            :ok

          {:error, reason} ->
            Logger.error(
              "[RecipeTranslationWorker] Failed to save translation: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "[RecipeTranslationWorker] Translation failed for recipe #{recipe_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def enqueue(recipe_id, language_name) do
    %{recipe_id: recipe_id, language_name: language_name}
    |> new()
    |> Oban.insert()
  end
end
