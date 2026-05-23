defmodule Mehungry.RecipeCreationWorker do
  use Oban.Worker,
    queue: :mailers,
    max_attempts: 3

  import Ecto.Query
  alias Mehungry.Posts.Post
  alias Mehungry.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"recipe_id" => recipe_id, "origin_url" => origin_url, "new_url" => new_url}
      }) do
    posts = Repo.all(from p in Post, where: p.reference_id == ^recipe_id)

    if !is_nil(origin_url) and origin_url != new_url do
      file_name = List.last(String.split(origin_url, "/"))

      ExAws.S3.delete_object("test-bucket-local-mehungry", file_name)
      |> ExAws.request(region: "eu-central-1")

      posts
      |> Enum.each(fn x ->
        Posts.update_post(x, %{md_media_url: new_url})
      end)
    end

    if length(posts) == 0 do
      recipe = Mehungry.Food.get_recipe!(recipe_id)
      create_post = Mehungry.Posts.create_post(recipe)
    end

    :ok
  end
end
