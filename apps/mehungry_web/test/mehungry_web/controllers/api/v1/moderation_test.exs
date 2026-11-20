defmodule MehungryWeb.Api.V1.ModerationTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures
  alias Mehungry.Moderation
  alias Mehungry.Posts

  setup :register_and_log_in_api_user

  defp recipe_with_post(author) do
    recipe = FoodFixtures.recipe_fixture(author)
    {:ok, _post} = Posts.create_post(recipe)
    recipe
  end

  defp comment_on(recipe, author) do
    {:ok, comment} =
      Posts.create_comment(%{"text" => "hello", "recipe_id" => recipe.id, "user_id" => author.id})

    comment
  end

  describe "POST /api/v1/reports" do
    test "files a report, then returns the same one for a repeat", %{conn: conn} do
      recipe = recipe_with_post(AccountsFixtures.user_fixture())
      body = %{target_type: "recipe", target_id: recipe.id, reason: "spam", note: "ad"}

      assert %{"data" => %{"id" => id, "status" => "open"}} =
               conn |> post(~p"/api/v1/reports", body) |> json_response(201)

      assert %{"data" => %{"id" => ^id}} =
               conn |> post(~p"/api/v1/reports", body) |> json_response(200)

      # The payload never carries the reporter.
      assert [report] = Moderation.list_reports()
      assert report.note == "ad"
    end

    test "validates the reason and target", %{conn: conn, user: me} do
      recipe = recipe_with_post(AccountsFixtures.user_fixture())

      assert %{"errors" => %{"fields" => %{"reason" => _}}} =
               conn
               |> post(~p"/api/v1/reports", %{
                 target_type: "recipe",
                 target_id: recipe.id,
                 reason: "meh"
               })
               |> json_response(422)

      assert conn
             |> post(~p"/api/v1/reports", %{target_type: "recipe", target_id: 0, reason: "spam"})
             |> json_response(404)

      assert conn
             |> post(~p"/api/v1/reports", %{target_type: "user", target_id: me.id, reason: "spam"})
             |> json_response(422)
    end

    test "requires authentication" do
      conn = Phoenix.ConnTest.build_conn()

      assert conn
             |> post(~p"/api/v1/reports", %{target_type: "user", target_id: 1, reason: "spam"})
             |> json_response(401)
    end
  end

  describe "blocks" do
    test "block, list, unblock", %{conn: conn} do
      them = AccountsFixtures.user_fixture()

      assert %{"data" => %{"blocked" => true}} =
               conn |> post(~p"/api/v1/users/#{them.id}/block") |> json_response(200)

      assert %{"data" => [%{"id" => id, "alias" => _, "avatar_url" => _, "blocked_at" => at}]} =
               conn |> get(~p"/api/v1/me/blocks") |> json_response(200)

      assert id == them.id
      assert String.ends_with?(at, "Z")

      assert %{"data" => %{"blocked" => false}} =
               conn |> delete(~p"/api/v1/users/#{them.id}/block") |> json_response(200)

      assert %{"data" => []} = conn |> get(~p"/api/v1/me/blocks") |> json_response(200)
    end

    test "cannot block yourself or an unknown user", %{conn: conn, user: me} do
      assert conn |> post(~p"/api/v1/users/#{me.id}/block") |> json_response(422)
      assert conn |> post(~p"/api/v1/users/0/block") |> json_response(404)
    end

    test "GET /users/:id reports blocked_by_me", %{conn: conn} do
      them = AccountsFixtures.user_fixture()

      assert %{"data" => %{"blocked_by_me" => false}} =
               conn |> get(~p"/api/v1/users/#{them.id}") |> json_response(200)

      conn |> post(~p"/api/v1/users/#{them.id}/block") |> json_response(200)

      assert %{"data" => %{"blocked_by_me" => true, "following" => false}} =
               conn |> get(~p"/api/v1/users/#{them.id}") |> json_response(200)

      assert %{"data" => %{"blocked_by_me" => false}} =
               Phoenix.ConnTest.build_conn()
               |> get(~p"/api/v1/users/#{them.id}")
               |> json_response(200)
    end
  end

  describe "a blocked user's content is hidden from the blocker" do
    setup %{conn: conn} do
      them = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()
      theirs = recipe_with_post(them)
      kept = recipe_with_post(other)
      comment_on(kept, them)
      kept_comment = comment_on(kept, other)

      conn |> post(~p"/api/v1/users/#{them.id}/block") |> json_response(200)

      %{them: them, theirs: theirs, kept: kept, kept_comment: kept_comment}
    end

    test "feed", %{conn: conn, theirs: theirs, kept: kept} do
      ids =
        conn
        |> get(~p"/api/v1/feed")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert kept.id in ids
      refute theirs.id in ids

      anon_ids =
        Phoenix.ConnTest.build_conn()
        |> get(~p"/api/v1/feed")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert theirs.id in anon_ids
    end

    test "recipe comments", %{conn: conn, kept: kept, kept_comment: kept_comment} do
      assert %{"data" => [%{"id" => id}]} =
               conn |> get(~p"/api/v1/recipes/#{kept.id}/comments") |> json_response(200)

      assert id == kept_comment.id

      assert %{"data" => [_, _]} =
               Phoenix.ConnTest.build_conn()
               |> get(~p"/api/v1/recipes/#{kept.id}/comments")
               |> json_response(200)
    end

    test "user recipes", %{conn: conn, them: them} do
      assert %{"data" => []} =
               conn |> get(~p"/api/v1/users/#{them.id}/recipes") |> json_response(200)

      assert %{"data" => [_]} =
               Phoenix.ConnTest.build_conn()
               |> get(~p"/api/v1/users/#{them.id}/recipes")
               |> json_response(200)
    end

    test "search", %{conn: conn, theirs: theirs} do
      term = theirs.title |> String.split() |> hd()

      ids =
        conn
        |> get(~p"/api/v1/search?q=#{term}")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      refute theirs.id in ids
    end
  end
end
