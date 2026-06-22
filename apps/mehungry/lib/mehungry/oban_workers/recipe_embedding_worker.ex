defmodule Mehungry.ObanWorkers.RecipeEmbeddingWorker do
  @moduledoc """
  Generates and stores a semantic embedding for a recipe.

  Triggered from Food.create_recipe/1, Food.update_recipe/2, and the
  one-time backfill (call enqueue_all/0 from iex to backfill existing recipes).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query

  alias Mehungry.{Repo, Food, AI.EmbeddingClient}
  alias Mehungry.Food.Recipe

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id}}) do
    recipe =
      Food.get_recipe_no_caching!(recipe_id)
      |> Repo.preload([recipe_ingredients: :ingredient, recipe_hashtags: :hashtag])

    text = build_text(recipe)

    case EmbeddingClient.embed(text) do
      {:ok, vector} ->
        Repo.update_all(
          from(r in Recipe, where: r.id == ^recipe_id),
          set: [embedding: Pgvector.new(vector)]
        )

        Logger.info("RecipeEmbeddingWorker: embedding stored for recipe #{recipe_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "RecipeEmbeddingWorker: embedding failed for recipe #{recipe_id}: #{reason}"
        )

        {:error, reason}
    end
  end

  @doc "Enqueue embedding generation for a single recipe."
  def enqueue(recipe_id) do
    %{recipe_id: recipe_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc "Enqueue embedding generation for all recipes missing an embedding."
  def enqueue_all do
    ids =
      Repo.all(from r in Recipe, where: is_nil(r.embedding), select: r.id)

    Enum.each(ids, &enqueue/1)
    Logger.info("RecipeEmbeddingWorker: enqueued #{length(ids)} recipes for backfill")
    length(ids)
  end

  defp build_text(recipe) do
    ingredients =
      recipe.recipe_ingredients
      |> Enum.map(fn ri -> ri.ingredient && ri.ingredient.name end)
      |> Enum.reject(&is_nil/1)

    hashtags =
      recipe.recipe_hashtags
      |> Enum.map(fn rh -> rh.hashtag && rh.hashtag.title end)
      |> Enum.reject(&is_nil/1)

    [
      recipe.title,
      recipe.description,
      recipe.cousine,
      if(ingredients != [], do: Enum.join(ingredients, ", ")),
      if(hashtags != [], do: Enum.join(hashtags, ", "))
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(". ")
  end
end
