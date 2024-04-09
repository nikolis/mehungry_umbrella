defmodule Mehungry.PostsTest do
  use Mehungry.DataCase


"""
  alias Mehungry.Posts

  describe "recipe_posts" do
    alias Mehungry.Posts.Post

    import Mehungry.PostsFixtures

    @invalid_attrs %{
      bg_media_url: nil,
      description: nil,
      md_media_url: nil,
      reference_url: nil,
      sm_media_url: nil,
      title: nil
    }

    test "list_recipe_posts/0 returns all recipe_posts" do
      recipe_post = recipe_post_fixture()
      assert Posts.list_recipe_posts() == [recipe_post]
    end

    test "get_recipe_post!/1 returns the recipe_post with given id" do
      recipe_post = recipe_post_fixture()
      assert Posts.get_recipe_post!(recipe_post.id) == recipe_post
    end

    test "create_recipe_post/1 with valid data creates a recipe_post" do
      valid_attrs = %{
        bg_media_url: "some bg_media_url",
        description: "some description",
        md_media_url: "some md_media_url",
        reference_url: "some reference_url",
        sm_media_url: "some sm_media_url",
        title: "some title"
      }

      assert {:ok, %Post{} = recipe_post} = Posts.create_recipe_post(valid_attrs)
      assert recipe_post.bg_media_url == "some bg_media_url"
      assert recipe_post.description == "some description"
      assert recipe_post.md_media_url == "some md_media_url"
      assert recipe_post.reference_url == "some reference_url"
      assert recipe_post.sm_media_url == "some sm_media_url"
      assert recipe_post.title == "some title"
    end

    test "create_recipe_post/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_recipe_post(@invalid_attrs)
    end

    test "update_recipe_post/2 with valid data updates the recipe_post" do
      recipe_post = recipe_post_fixture()

      update_attrs = %{
        bg_media_url: "some updated bg_media_url",
        description: "some updated description",
        md_media_url: "some updated md_media_url",
        reference_url: "some updated reference_url",
        sm_media_url: "some updated sm_media_url",
        title: "some updated title"
      }

      assert {:ok, %Post{} = recipe_post} =
               Posts.update_recipe_post(recipe_post, update_attrs)

      assert recipe_post.bg_media_url == "some updated bg_media_url"
      assert recipe_post.description == "some updated description"
      assert recipe_post.md_media_url == "some updated md_media_url"
      assert recipe_post.reference_url == "some updated reference_url"
      assert recipe_post.sm_media_url == "some updated sm_media_url"
      assert recipe_post.title == "some updated title"
    end

    test "update_recipe_post/2 with invalid data returns error changeset" do
      recipe_post = recipe_post_fixture()
      assert {:error, %Ecto.Changeset{}} = Posts.update_recipe_post(recipe_post, @invalid_attrs)
      assert recipe_post == Posts.get_recipe_post!(recipe_post.id)
    end

    test "delete_recipe_post/1 deletes the recipe_post" do
      recipe_post = recipe_post_fixture()
      assert {:ok, %Post{}} = Posts.delete_recipe_post(recipe_post)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_recipe_post!(recipe_post.id) end
    end

    test "change_recipe_post/1 returns a recipe_post changeset" do
      recipe_post = recipe_post_fixture()
      assert %Ecto.Changeset{} = Posts.change_recipe_post(recipe_post)
    end
  end

  describe "posts" do
    alias Mehungry.Posts.Post

    import Mehungry.PostsFixtures

    @invalid_attrs %{
      bg_media_url: nil,
      description: nil,
      md_media_url: nil,
      reference_id: nil,
      reference_url: nil,
      sm_media_url: nil,
      title: nil,
      type_: nil
    }

    test "list_posts/0 returns all posts" do
      post = post_fixture()
      assert Posts.list_posts() == [post]
    end

    test "get_post!/1 returns the post with given id" do
      post = post_fixture()
      assert Posts.get_post!(post.id) == post
    end

    test "create_post/1 with valid data creates a post" do
      valid_attrs = %{
        bg_media_url: "some bg_media_url",
        description: "some description",
        md_media_url: "some md_media_url",
        reference_id: 42,
        reference_url: "some reference_url",
        sm_media_url: "some sm_media_url",
        title: "some title",
        type_: "some type_"
      }

      assert {:ok, %Post{} = post} = Posts.create_post(valid_attrs)
      assert post.bg_media_url == "some bg_media_url"
      assert post.description == "some description"
      assert post.md_media_url == "some md_media_url"
      assert post.reference_id == 42
      assert post.reference_url == "some reference_url"
      assert post.sm_media_url == "some sm_media_url"
      assert post.title == "some title"
      assert post.type_ == "some type_"
    end

    test "create_post/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_post(@invalid_attrs)
    end

    test "update_post/2 with valid data updates the post" do
      post = post_fixture()

      update_attrs = %{
        bg_media_url: "some updated bg_media_url",
        description: "some updated description",
        md_media_url: "some updated md_media_url",
        reference_id: 43,
        reference_url: "some updated reference_url",
        sm_media_url: "some updated sm_media_url",
        title: "some updated title",
        type_: "some updated type_"
      }

      assert {:ok, %Post{} = post} = Posts.update_post(post, update_attrs)
      assert post.bg_media_url == "some updated bg_media_url"
      assert post.description == "some updated description"
      assert post.md_media_url == "some updated md_media_url"
      assert post.reference_id == 43
      assert post.reference_url == "some updated reference_url"
      assert post.sm_media_url == "some updated sm_media_url"
      assert post.title == "some updated title"
      assert post.type_ == "some updated type_"
    end

    test "update_post/2 with invalid data returns error changeset" do
      post = post_fixture()
      assert {:error, %Ecto.Changeset{}} = Posts.update_post(post, @invalid_attrs)
      assert post == Posts.get_post!(post.id)
    end

    test "delete_post/1 deletes the post" do
      post = post_fixture()
      assert {:ok, %Post{}} = Posts.delete_post(post)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_post!(post.id) end
    end

    test "change_post/1 returns a post changeset" do
      post = post_fixture()
      assert %Ecto.Changeset{} = Posts.change_post(post)
    end
  end

  describe "comments" do
    alias Mehungry.Posts.Comment

    import Mehungry.PostsFixtures

    @invalid_attrs %{text: nil}

    test "list_comments/0 returns all comments" do
      comment = comment_fixture()
      assert Posts.list_comments() == [comment]
    end

    test "get_comment!/1 returns the comment with given id" do
      comment = comment_fixture()
      assert Posts.get_comment!(comment.id) == comment
    end

    test "create_comment/1 with valid data creates a comment" do
      valid_attrs = %{text: "some text"}

      assert {:ok, %Comment{} = comment} = Posts.create_comment(valid_attrs)
      assert comment.text == "some text"
    end

    test "create_comment/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_comment(@invalid_attrs)
    end

    test "update_comment/2 with valid data updates the comment" do
      comment = comment_fixture()
      update_attrs = %{text: "some updated text"}

      assert {:ok, %Comment{} = comment} = Posts.update_comment(comment, update_attrs)
      assert comment.text == "some updated text"
    end

    test "update_comment/2 with invalid data returns error changeset" do
      comment = comment_fixture()
      assert {:error, %Ecto.Changeset{}} = Posts.update_comment(comment, @invalid_attrs)
      assert comment == Posts.get_comment!(comment.id)
    end

    test "delete_comment/1 deletes the comment" do
      comment = comment_fixture()
      assert {:ok, %Comment{}} = Posts.delete_comment(comment)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_comment!(comment.id) end
    end

    test "change_comment/1 returns a comment changeset" do
      comment = comment_fixture()
      assert %Ecto.Changeset{} = Posts.change_comment(comment)
    end
  end

  describe "comment_answers" do
    alias Mehungry.Posts.CommentAnswer

    import Mehungry.PostsFixtures

    @invalid_attrs %{text: nil}

    test "list_comment_answers/0 returns all comment_answers" do
      comment_answer = comment_answer_fixture()
      assert Posts.list_comment_answers() == [comment_answer]
    end

    test "get_comment_answer!/1 returns the comment_answer with given id" do
      comment_answer = comment_answer_fixture()
      assert Posts.get_comment_answer!(comment_answer.id) == comment_answer
    end

    test "create_comment_answer/1 with valid data creates a comment_answer" do
      valid_attrs = %{text: "some text"}

      assert {:ok, %CommentAnswer{} = comment_answer} = Posts.create_comment_answer(valid_attrs)
      assert comment_answer.text == "some text"
    end

    test "create_comment_answer/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_comment_answer(@invalid_attrs)
    end

    test "update_comment_answer/2 with valid data updates the comment_answer" do
      comment_answer = comment_answer_fixture()
      update_attrs = %{text: "some updated text"}

      assert {:ok, %CommentAnswer{} = comment_answer} =
               Posts.update_comment_answer(comment_answer, update_attrs)

      assert comment_answer.text == "some updated text"
    end

    test "update_comment_answer/2 with invalid data returns error changeset" do
      comment_answer = comment_answer_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Posts.update_comment_answer(comment_answer, @invalid_attrs)

      assert comment_answer == Posts.get_comment_answer!(comment_answer.id)
    end

    test "delete_comment_answer/1 deletes the comment_answer" do
      comment_answer = comment_answer_fixture()
      assert {:ok, %CommentAnswer{}} = Posts.delete_comment_answer(comment_answer)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_comment_answer!(comment_answer.id) end
    end

    test "change_comment_answer/1 returns a comment_answer changeset" do
      comment_answer = comment_answer_fixture()
      assert %Ecto.Changeset{} = Posts.change_comment_answer(comment_answer)
    end
  end

  describe "post_upvotes" do
    alias Mehungry.Posts.PostUpvote

    import Mehungry.PostsFixtures

    @invalid_attrs %{}

    test "list_post_upvotes/0 returns all post_upvotes" do
      post_upvote = post_upvote_fixture()
      assert Posts.list_post_upvotes() == [post_upvote]
    end

    test "get_post_upvote!/1 returns the post_upvote with given id" do
      post_upvote = post_upvote_fixture()
      assert Posts.get_post_upvote!(post_upvote.id) == post_upvote
    end

    test "create_post_upvote/1 with valid data creates a post_upvote" do
      valid_attrs = %{}

      assert {:ok, %PostUpvote{} = post_upvote} = Posts.create_post_upvote(valid_attrs)
    end

    test "create_post_upvote/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_post_upvote(@invalid_attrs)
    end

    test "update_post_upvote/2 with valid data updates the post_upvote" do
      post_upvote = post_upvote_fixture()
      update_attrs = %{}

      assert {:ok, %PostUpvote{} = post_upvote} =
               Posts.update_post_upvote(post_upvote, update_attrs)
    end

    test "update_post_upvote/2 with invalid data returns error changeset" do
      post_upvote = post_upvote_fixture()
      assert {:error, %Ecto.Changeset{}} = Posts.update_post_upvote(post_upvote, @invalid_attrs)
      assert post_upvote == Posts.get_post_upvote!(post_upvote.id)
    end

    test "delete_post_upvote/1 deletes the post_upvote" do
      post_upvote = post_upvote_fixture()
      assert {:ok, %PostUpvote{}} = Posts.delete_post_upvote(post_upvote)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_post_upvote!(post_upvote.id) end
    end

    test "change_post_upvote/1 returns a post_upvote changeset" do
      post_upvote = post_upvote_fixture()
      assert %Ecto.Changeset{} = Posts.change_post_upvote(post_upvote)
    end
  end

  describe "post_downvotes" do
    alias Mehungry.Posts.PostDownvote

    import Mehungry.PostsFixtures

    @invalid_attrs %{}

    test "list_post_downvotes/0 returns all post_downvotes" do
      post_downvote = post_downvote_fixture()
      assert Posts.list_post_downvotes() == [post_downvote]
    end

    test "get_post_downvote!/1 returns the post_downvote with given id" do
      post_downvote = post_downvote_fixture()
      assert Posts.get_post_downvote!(post_downvote.id) == post_downvote
    end

    test "create_post_downvote/1 with valid data creates a post_downvote" do
      valid_attrs = %{}

      assert {:ok, %PostDownvote{} = post_downvote} = Posts.create_post_downvote(valid_attrs)
    end

    test "create_post_downvote/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_post_downvote(@invalid_attrs)
    end

    test "update_post_downvote/2 with valid data updates the post_downvote" do
      post_downvote = post_downvote_fixture()
      update_attrs = %{}

      assert {:ok, %PostDownvote{} = post_downvote} =
               Posts.update_post_downvote(post_downvote, update_attrs)
    end

    test "update_post_downvote/2 with invalid data returns error changeset" do
      post_downvote = post_downvote_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Posts.update_post_downvote(post_downvote, @invalid_attrs)

      assert post_downvote == Posts.get_post_downvote!(post_downvote.id)
    end

    test "delete_post_downvote/1 deletes the post_downvote" do
      post_downvote = post_downvote_fixture()
      assert {:ok, %PostDownvote{}} = Posts.delete_post_downvote(post_downvote)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_post_downvote!(post_downvote.id) end
    end

    test "change_post_downvote/1 returns a post_downvote changeset" do
      post_downvote = post_downvote_fixture()
      assert %Ecto.Changeset{} = Posts.change_post_downvote(post_downvote)
    end
  end

  describe "comment_votes" do
    alias Mehungry.Posts.CommentVote

    import Mehungry.PostsFixtures

    @invalid_attrs %{positive: nil}

    test "list_comment_votes/0 returns all comment_votes" do
      comment_vote = comment_vote_fixture()
      assert Posts.list_comment_votes() == [comment_vote]
    end

    test "get_comment_vote!/1 returns the comment_vote with given id" do
      comment_vote = comment_vote_fixture()
      assert Posts.get_comment_vote!(comment_vote.id) == comment_vote
    end

    test "create_comment_vote/1 with valid data creates a comment_vote" do
      valid_attrs = %{positive: true}

      assert {:ok, %CommentVote{} = comment_vote} = Posts.create_comment_vote(valid_attrs)
      assert comment_vote.positive == true
    end

    test "create_comment_vote/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_comment_vote(@invalid_attrs)
    end

    test "update_comment_vote/2 with valid data updates the comment_vote" do
      comment_vote = comment_vote_fixture()
      update_attrs = %{positive: false}

      assert {:ok, %CommentVote{} = comment_vote} =
               Posts.update_comment_vote(comment_vote, update_attrs)

      assert comment_vote.positive == false
    end

    test "update_comment_vote/2 with invalid data returns error changeset" do
      comment_vote = comment_vote_fixture()
      assert {:error, %Ecto.Changeset{}} = Posts.update_comment_vote(comment_vote, @invalid_attrs)
      assert comment_vote == Posts.get_comment_vote!(comment_vote.id)
    end

    test "delete_comment_vote/1 deletes the comment_vote" do
      comment_vote = comment_vote_fixture()
      assert {:ok, %CommentVote{}} = Posts.delete_comment_vote(comment_vote)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_comment_vote!(comment_vote.id) end
    end

    test "change_comment_vote/1 returns a comment_vote changeset" do
      comment_vote = comment_vote_fixture()
      assert %Ecto.Changeset{} = Posts.change_comment_vote(comment_vote)
    end
  end

  describe "comment_answer_votes" do
    alias Mehungry.Posts.CommentAnswerVote

    import Mehungry.PostsFixtures

    @invalid_attrs %{positive: nil}

    test "list_comment_answer_votes/0 returns all comment_answer_votes" do
      comment_answer_vote = comment_answer_vote_fixture()
      assert Posts.list_comment_answer_votes() == [comment_answer_vote]
    end

    test "get_comment_answer_vote!/1 returns the comment_answer_vote with given id" do
      comment_answer_vote = comment_answer_vote_fixture()
      assert Posts.get_comment_answer_vote!(comment_answer_vote.id) == comment_answer_vote
    end

    test "create_comment_answer_vote/1 with valid data creates a comment_answer_vote" do
      valid_attrs = %{positive: true}

      assert {:ok, %CommentAnswerVote{} = comment_answer_vote} =
               Posts.create_comment_answer_vote(valid_attrs)

      assert comment_answer_vote.positive == true
    end

    test "create_comment_answer_vote/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_comment_answer_vote(@invalid_attrs)
    end

    test "update_comment_answer_vote/2 with valid data updates the comment_answer_vote" do
      comment_answer_vote = comment_answer_vote_fixture()
      update_attrs = %{positive: false}

      assert {:ok, %CommentAnswerVote{} = comment_answer_vote} =
               Posts.update_comment_answer_vote(comment_answer_vote, update_attrs)

      assert comment_answer_vote.positive == false
    end

    test "update_comment_answer_vote/2 with invalid data returns error changeset" do
      comment_answer_vote = comment_answer_vote_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Posts.update_comment_answer_vote(comment_answer_vote, @invalid_attrs)

      assert comment_answer_vote == Posts.get_comment_answer_vote!(comment_answer_vote.id)
    end

    test "delete_comment_answer_vote/1 deletes the comment_answer_vote" do
      comment_answer_vote = comment_answer_vote_fixture()
      assert {:ok, %CommentAnswerVote{}} = Posts.delete_comment_answer_vote(comment_answer_vote)

      assert_raise Ecto.NoResultsError, fn ->
        Posts.get_comment_answer_vote!(comment_answer_vote.id)
      end
    end

    test "change_comment_answer_vote/1 returns a comment_answer_vote changeset" do
      comment_answer_vote = comment_answer_vote_fixture()
      assert %Ecto.Changeset{} = Posts.change_comment_answer_vote(comment_answer_vote)
    end
  end
  """
end
