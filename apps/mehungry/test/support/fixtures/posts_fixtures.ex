defmodule Mehungry.PostsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Posts` context.
  """

  @doc """
  Generate a recipe_post.
  """
  def recipe_post_fixture(attrs \\ %{}) do
    {:ok, recipe_post} =
      attrs
      |> Enum.into(%{
        bg_media_url: "some bg_media_url",
        description: "some description",
        md_media_url: "some md_media_url",
        reference_url: "some reference_url",
        sm_media_url: "some sm_media_url",
        title: "some title"
      })
      |> Mehungry.Posts.create_recipe_post()

    recipe_post
  end

  @doc """
  Generate a post.
  """
  def post_fixture(attrs \\ %{}) do
    {:ok, post} =
      attrs
      |> Enum.into(%{
        bg_media_url: "some bg_media_url",
        description: "some description",
        md_media_url: "some md_media_url",
        reference_id: 42,
        reference_url: "some reference_url",
        sm_media_url: "some sm_media_url",
        title: "some title",
        type_: "some type_"
      })
      |> Mehungry.Posts.create_post()

    post
  end

  @doc """
  Generate a comment.
  """
  def comment_fixture(attrs \\ %{}) do
    {:ok, comment} =
      attrs
      |> Enum.into(%{
        text: "some text"
      })
      |> Mehungry.Posts.create_comment()

    comment
  end

  @doc """
  Generate a comment_answer.
  """
  def comment_answer_fixture(attrs \\ %{}) do
    {:ok, comment_answer} =
      attrs
      |> Enum.into(%{
        text: "some text"
      })
      |> Mehungry.Posts.create_comment_answer()

    comment_answer
  end

  @doc """
  Generate a post_upvote.
  """
  def post_upvote_fixture(attrs \\ %{}) do
    {:ok, post_upvote} =
      attrs
      |> Enum.into(%{})
      |> Mehungry.Posts.create_post_upvote()

    post_upvote
  end

  @doc """
  Generate a post_downvote.
  """
  def post_downvote_fixture(attrs \\ %{}) do
    {:ok, post_downvote} =
      attrs
      |> Enum.into(%{})
      |> Mehungry.Posts.create_post_downvote()

    post_downvote
  end

  @doc """
  Generate a comment_vote.
  """
  def comment_vote_fixture(attrs \\ %{}) do
    {:ok, comment_vote} =
      attrs
      |> Enum.into(%{
        positive: true
      })
      |> Mehungry.Posts.create_comment_vote()

    comment_vote
  end

  @doc """
  Generate a comment_answer_vote.
  """
  def comment_answer_vote_fixture(attrs \\ %{}) do
    {:ok, comment_answer_vote} =
      attrs
      |> Enum.into(%{
        positive: true
      })
      |> Mehungry.Posts.create_comment_answer_vote()

    comment_answer_vote
  end
end
