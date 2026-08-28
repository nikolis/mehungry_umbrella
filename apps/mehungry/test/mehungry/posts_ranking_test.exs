defmodule Mehungry.PostsRankingTest do
  use Mehungry.DataCase

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Posts
  alias Mehungry.Posts.Post
  alias Mehungry.Repo

  # Insert a post authored by `user`, referencing a real recipe, at a chosen
  # inserted_at so recency-based ranking can be exercised.
  defp post_at(user, naive_dt) do
    recipe = recipe_fixture(user)

    post =
      Repo.insert!(%Post{
        user_id: user.id,
        reference_id: recipe.id,
        title: "post #{System.unique_integer([:positive])}",
        md_media_url: "some md_media_url",
        type_: "recipe",
        inserted_at: naive_dt,
        updated_at: naive_dt
      })

    post.id
  end

  describe "AI content down-ranking (Mehungry.Posts.list_posts/1)" do
    setup do
      [bot_email | _] = Application.get_env(:mehungry, :ai_bot_emails)
      bot = user_fixture(%{email: bot_email})
      human = user_fixture(%{email: "human_feed#{System.unique_integer([:positive])}@example.com"})
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # AI post is 2h old; human post is 2.5 days old.
      bot_post_id = post_at(bot, NaiveDateTime.add(now, -2 * 3600, :second))
      human_post_id = post_at(human, NaiveDateTime.add(now, -60 * 3600, :second))

      %{bot_post_id: bot_post_id, human_post_id: human_post_id}
    end

    test "anonymous feed ranks the older human post above the fresh AI post", ctx do
      ids = Posts.list_posts(nil) |> Enum.map(& &1.id)

      assert Enum.find_index(ids, &(&1 == ctx.human_post_id)) <
               Enum.find_index(ids, &(&1 == ctx.bot_post_id))
    end

    test "without the penalty the fresh AI post ranks first (sanity check)", ctx do
      original = Application.get_env(:mehungry, :ai_content_penalty)
      Application.put_env(:mehungry, :ai_content_penalty, 0.0)
      on_exit(fn -> Application.put_env(:mehungry, :ai_content_penalty, original) end)

      ids = Posts.list_posts(nil) |> Enum.map(& &1.id)

      assert Enum.find_index(ids, &(&1 == ctx.bot_post_id)) <
               Enum.find_index(ids, &(&1 == ctx.human_post_id))
    end
  end
end
