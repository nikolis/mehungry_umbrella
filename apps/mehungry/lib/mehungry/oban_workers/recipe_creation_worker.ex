defmodule Mehungry.RecipeCreationWorker do
  use Oban.Worker,
    queue: :mailers,
    max_attempts: 3

  import Ecto.Query
  alias Mehungry.Posts
  alias Mehungry.Posts.Post
  alias Mehungry.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"recipe_id" => recipe_id, "origin_url" => origin_url, "new_url" => new_url}
      }) do
    posts = Repo.all(from p in Post, where: p.reference_id == ^recipe_id)

    if !is_nil(origin_url) and origin_url != new_url do
      Mehungry.Storage.delete_by_url(origin_url)

      posts
      |> Enum.each(fn x ->
        Posts.update_post(x, %{md_media_url: new_url})
      end)
    end

    # Post backfill (creating a post for a recipe that never got one) is handled
    # idempotently by RecipePutNutrientsWorker, which runs on every update. This
    # worker only keeps existing posts' media in sync with the recipe's image.
    :ok
  end
end
