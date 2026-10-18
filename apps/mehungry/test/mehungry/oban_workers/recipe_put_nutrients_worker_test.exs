defmodule Mehungry.RecipePutNutrientsWorkerTest do
  use Mehungry.DataCase

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Posts
  alias Mehungry.RecipePutNutrientsWorker

  defp perform(recipe_id) do
    RecipePutNutrientsWorker.perform(%Oban.Job{args: %{"recipe_id" => recipe_id}})
  end

  defp post_count(recipe_id) do
    import Ecto.Query

    Mehungry.Repo.aggregate(
      from(p in Posts.Post, where: p.reference_id == ^recipe_id and is_nil(p.language_name)),
      :count
    )
  end

  describe "post backfill" do
    setup do
      %{user: user_fixture()}
    end

    test "creates a post for a recipe that has an image but no post yet", %{user: user} do
      recipe = recipe_fixture(user, image_url: "https://example.com/image.jpg")
      # recipe_fixture -> create_recipe enqueues (not runs) the worker, so no post exists yet.
      assert post_count(recipe.id) == 0

      assert {:ok, _} = perform(recipe.id)
      assert post_count(recipe.id) == 1
    end

    test "does not create a duplicate post when run again (idempotent)", %{user: user} do
      recipe = recipe_fixture(user, image_url: "https://example.com/image.jpg")

      assert {:ok, _} = perform(recipe.id)
      assert {:ok, _} = perform(recipe.id)
      assert {:ok, _} = perform(recipe.id)

      assert post_count(recipe.id) == 1
    end

    test "backfills a post once an image-less recipe gains an image on update", %{user: user} do
      recipe = recipe_fixture(user, image_url: "")

      # No image at creation -> running the worker can't create a post (a post
      # requires md_media_url, sourced from image_url).
      assert {:ok, _} = perform(recipe.id)
      assert post_count(recipe.id) == 0

      {:ok, recipe} = Mehungry.Food.update_recipe(recipe, %{"image_url" => "https://example.com/i.jpg"})

      # Running the worker on the now-imaged recipe backfills the post.
      assert {:ok, _} = perform(recipe.id)
      assert post_count(recipe.id) == 1
    end
  end
end
