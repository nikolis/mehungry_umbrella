defmodule Mehungry.Posts do
  alias Mehungry.Posts.CommentVote 

  @moduledoc """
  The Posts context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Posts.Post

  @doc """
  Returns the list of posts.

  ## Examples

      iex> list_posts()
      [%Post{}, ...]

  """
  def list_posts do
    Repo.all(Post)
    |> Repo.preload([:upvotes, :downvotes, comments: [:user]])
  end

  def subscribe_to_post(%{post_id: post_id}) do
    Phoenix.PubSub.subscribe(Mehungry.PubSub, "post:" <> to_string(post_id))
  end



  defp broadcast_vote({:ok, vote}, type_) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, "post:" <> to_string(vote.post_id), %{
      new_vote: vote,
      type_: type_
    })

    {:ok, vote}
  end


  defp broadcast_change({:ok, comment}) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, "post:" <> to_string(comment.post_id), %{
      new_comment: comment
    })

    {:ok, comment}
  end

  @doc """
  Gets a single post.

  Raises `Ecto.NoResultsError` if the Post does not exist.

  ## Examples

      iex> get_post!(123)
      %Post{}

      iex> get_post!(456)
      ** (Ecto.NoResultsError)

  """
  def get_post!(id) do
    Repo.get!(Post, id)
    |> Repo.preload([:upvotes, :downvotes, comments: [:user, votes: [:user] ,comment_answers: [:user, votes: [:user]]]])
  end

  @doc """
  Creates a post.

  ## Examples

      iex> create_post(%{field: value})
      {:ok, %Post{}}

      iex> create_post(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a post.

  ## Examples

      iex> update_post(post, %{field: new_value})
      {:ok, %Post{}}

      iex> update_post(post, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a post.

  ## Examples

      iex> delete_post(post)
      {:ok, %Post{}}

      iex> delete_post(post)
      {:error, %Ecto.Changeset{}}

  """
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.

  ## Examples

      iex> change_post(post)
      %Ecto.Changeset{data: %Post{}}

  """
  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  alias Mehungry.Posts.Comment

  @doc """
  Returns the list of comments.

  ## Examples

      iex> list_comments()
      [%Comment{}, ...]

  """
  def list_comments do
    Repo.all(Comment)
  end

  @doc """
  Gets a single comment.

  Raises `Ecto.NoResultsError` if the Comment does not exist.

  ## Examples

      iex> get_comment!(123)
      %Comment{}

      iex> get_comment!(456)
      ** (Ecto.NoResultsError)

  """
  def get_comment!(id) do
    Repo.get!(Comment, id)
    |> Repo.preload([:user, comment_answers: [:user, votes: [:user]], votes: [:user] ])
  end

  @doc """
  Creates a comment.

  ## Examples

      iex> create_comment(%{field: value})
      {:ok, %Comment{}}

      iex> create_comment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment(attrs \\ %{}) do
    result =
      %Comment{}
      |> Comment.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, comment} ->
        broadcast_change(result)
        result

      {:error, _} ->
        result
    end
  end

  @doc """
  Updates a comment.

  ## Examples

      iex> update_comment(comment, %{field: new_value})
      {:ok, %Comment{}}

      iex> update_comment(comment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment(%Comment{} = comment, attrs) do
    comment
    |> Comment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a comment.

  ## Examples

      iex> delete_comment(comment)
      {:ok, %Comment{}}

      iex> delete_comment(comment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_comment(%Comment{} = comment) do
    Repo.delete(comment)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment changes.

  ## Examples

      iex> change_comment(comment)
      %Ecto.Changeset{data: %Comment{}}

  """
  def change_comment(%Comment{} = comment, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  alias Mehungry.Posts.CommentAnswer

  @doc """
  Returns the list of comment_answers.

  ## Examples

      iex> list_comment_answers()
      [%CommentAnswer{}, ...]

  """
  def list_comment_answers do
    Repo.all(CommentAnswer)
  end

  @doc """
  Gets a single comment_answer.

  Raises `Ecto.NoResultsError` if the Comment answer does not exist.

  ## Examples

      iex> get_comment_answer!(123)
      %CommentAnswer{}

      iex> get_comment_answer!(456)
      ** (Ecto.NoResultsError)

  """
  def get_comment_answer!(id), do: Repo.get!(CommentAnswer, id)

  @doc """
  Creates a comment_answer.

  ## Examples

      iex> create_comment_answer(%{field: value})
      {:ok, %CommentAnswer{}}

      iex> create_comment_answer(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment_answer(attrs \\ %{}) do
    result = 
      %CommentAnswer{}
      |> CommentAnswer.changeset(attrs)
      |> Repo.insert()
    case result do 
      {:ok, comment_answer} ->
        comment = get_comment!(comment_answer.comment_id)
        broadcast_change({:ok, comment})
        result
      {:error, _ } ->
        result
    end
  end

  @doc """
  Updates a comment_answer.

  ## Examples

      iex> update_comment_answer(comment_answer, %{field: new_value})
      {:ok, %CommentAnswer{}}

      iex> update_comment_answer(comment_answer, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment_answer(%CommentAnswer{} = comment_answer, attrs) do
    comment_answer
    |> CommentAnswer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a comment_answer.

  ## Examples

      iex> delete_comment_answer(comment_answer)
      {:ok, %CommentAnswer{}}

      iex> delete_comment_answer(comment_answer)
      {:error, %Ecto.Changeset{}}

  """
  def delete_comment_answer(%CommentAnswer{} = comment_answer) do
    Repo.delete(comment_answer)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment_answer changes.

  ## Examples

      iex> change_comment_answer(comment_answer)
      %Ecto.Changeset{data: %CommentAnswer{}}

  """
  def change_comment_answer(%CommentAnswer{} = comment_answer, attrs \\ %{}) do
    CommentAnswer.changeset(comment_answer, attrs)
  end

  alias Mehungry.Posts.PostUpvote

  @doc """
  Returns the list of post_upvotes.

  ## Examples

      iex> list_post_upvotes()
      [%PostUpvote{}, ...]

  """
  def list_post_upvotes do
    Repo.all(PostUpvote)
  end

  @doc """
  Gets a single post_upvote.

  Raises `Ecto.NoResultsError` if the Post upvote does not exist.

  ## Examples

      iex> get_post_upvote!(123)
      %PostUpvote{}

      iex> get_post_upvote!(456)
      ** (Ecto.NoResultsError)

  """
  def get_post_upvote!(id), do: Repo.get!(PostUpvote, id)

  @doc """
  Creates a post_upvote.

  ## Examples

      iex> create_post_upvote(%{field: value})
      {:ok, %PostUpvote{}}

      iex> create_post_upvote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_post_upvote(attrs \\ %{}) do
    %PostUpvote{}
    |> PostUpvote.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a post_upvote.

  ## Examples

      iex> update_post_upvote(post_upvote, %{field: new_value})
      {:ok, %PostUpvote{}}

      iex> update_post_upvote(post_upvote, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_post_upvote(%PostUpvote{} = post_upvote, attrs) do
    post_upvote
    |> PostUpvote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a post_upvote.

  ## Examples

      iex> delete_post_upvote(post_upvote)
      {:ok, %PostUpvote{}}

      iex> delete_post_upvote(post_upvote)
      {:error, %Ecto.Changeset{}}

  """
  def delete_post_upvote(%PostUpvote{} = post_upvote) do
    Repo.delete(post_upvote)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post_upvote changes.

  ## Examples

      iex> change_post_upvote(post_upvote)
      %Ecto.Changeset{data: %PostUpvote{}}

  """
  def change_post_upvote(%PostUpvote{} = post_upvote, attrs \\ %{}) do
    PostUpvote.changeset(post_upvote, attrs)
  end

  alias Mehungry.Posts.PostDownvote

  @doc """
  Returns the list of post_downvotes.

  ## Examples

      iex> list_post_downvotes()
      [%PostDownvote{}, ...]

  """
  def list_post_downvotes do
    Repo.all(PostDownvote)
  end

  @doc """
  Gets a single post_downvote.

  Raises `Ecto.NoResultsError` if the Post downvote does not exist.

  ## Examples

      iex> get_post_downvote!(123)
      %PostDownvote{}

      iex> get_post_downvote!(456)
      ** (Ecto.NoResultsError)

  """
  def get_post_downvote!(id), do: Repo.get!(PostDownvote, id)

  @doc """
  Creates a post_downvote.

  ## Examples

      iex> create_post_downvote(%{field: value})
      {:ok, %PostDownvote{}}

      iex> create_post_downvote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_post_downvote(attrs \\ %{}) do
    %PostDownvote{}
    |> PostDownvote.changeset(attrs)
    |> Repo.insert()
  end

  def downvote_post(post_id, user_id) do
    downvote = get_downvote_from(user_id, post_id)
    upvote = get_upvote_from(user_id, post_id)

    if upvote do
      delete_upvotes(user_id, post_id)
    end

    if not Enum.empty?(downvote) do 
      delete_downvotes(user_id, post_id)
      broadcast_vote({:ok, %{post_id: post_id}}, "downvote")
      :already_downvoted
    else 
      result = 
        %PostDownvote{}
        |> PostDownvote.changeset(%{user_id: user_id, post_id: post_id})
        |> Repo.insert()

      broadcast_vote(result, "downvote")

    end
  end

  def get_comment_votes_for_user(user_id, comment_id) do
    (from c in CommentVote, 
    where: c.user_id == ^user_id and c.comment_id ==^comment_id)
    |> Repo.one()
  end

  def vote_comment(comment_id, user_id, reaction) do
    vote = get_comment_votes_for_user(user_id, comment_id)
    comment = get_comment!(comment_id) 
    get_positive = fn a -> 
      case a do 
        "true" ->
          true
        "false" ->
          false
       end
    end

    if not is_nil(vote)  and vote.positive != reaction do
      vote = update_comment_vote(vote, %{positive: (get_positive.(reaction))}) 
      broadcast_vote({:ok, comment}, "vote")

    else
      result =
        %CommentVote{}
        |> CommentVote.changeset(%{user_id: user_id, comment_id: comment_id, positive: reaction})
        |> Repo.insert()

      broadcast_vote({:ok, comment}, "vote")

    end
  end



  def upvote_post(post_id, user_id) do
    downvote = get_downvote_from(user_id, post_id)
    upvote = get_upvote_from(user_id, post_id)

    if downvote do
      delete_downvotes(user_id, post_id)
    end

    if not Enum.empty?(upvote) do 
      delete_upvotes(user_id, post_id)
      broadcast_vote({:ok, %{post_id: post_id}}, "downvote")

      :already_downvoted
    else
      result =
        %PostUpvote{}
        |> PostUpvote.changeset(%{user_id: user_id, post_id: post_id})
        |> Repo.insert()

      broadcast_vote(result, "upvote")

    end
  end


  def delete_upvotes(user_id, post_id) do
    from(upvote in PostUpvote,
      where: upvote.user_id == ^user_id and upvote.post_id == ^post_id
    )
    |> Repo.delete_all()
  end

  def delete_downvotes(user_id, post_id) do
    from(downvote in PostDownvote,
      where: downvote.user_id == ^user_id and downvote.post_id == ^post_id
    )
    |> Repo.delete_all()

  end

  def get_downvote_from(user_id, post_id) do
    from(downvote in PostDownvote,
      where: downvote.user_id == ^user_id and downvote.post_id == ^post_id
    )
    |> Repo.all()
  end

  def get_upvote_from(user_id, post_id) do
    from(upvote in PostUpvote,
      where: upvote.user_id == ^user_id and upvote.post_id == ^post_id
    )
    |> Repo.all()
  end

  @doc """
  Updates a post_downvote.

  ## Examples

      iex> update_post_downvote(post_downvote, %{field: new_value})
      {:ok, %PostDownvote{}}

      iex> update_post_downvote(post_downvote, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_post_downvote(%PostDownvote{} = post_downvote, attrs) do
    post_downvote
    |> PostDownvote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a post_downvote.

  ## Examples

      iex> delete_post_downvote(post_downvote)
      {:ok, %PostDownvote{}}

      iex> delete_post_downvote(post_downvote)
      {:error, %Ecto.Changeset{}}

  """
  def delete_post_downvote(%PostDownvote{} = post_downvote) do
    Repo.delete(post_downvote)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post_downvote changes.

  ## Examples

      iex> change_post_downvote(post_downvote)
      %Ecto.Changeset{data: %PostDownvote{}}

  """
  def change_post_downvote(%PostDownvote{} = post_downvote, attrs \\ %{}) do
    PostDownvote.changeset(post_downvote, attrs)
  end

  alias Mehungry.Posts.CommentVote

  @doc """
  Returns the list of comment_votes.

  ## Examples

      iex> list_comment_votes()
      [%CommentVote{}, ...]

  """
  def list_comment_votes do
    Repo.all(CommentVote)
  end

  @doc """
  Gets a single comment_vote.

  Raises `Ecto.NoResultsError` if the Comment vote does not exist.

  ## Examples

      iex> get_comment_vote!(123)
      %CommentVote{}

      iex> get_comment_vote!(456)
      ** (Ecto.NoResultsError)

  """
  def get_comment_vote!(id), do: Repo.get!(CommentVote, id)

  @doc """
  Creates a comment_vote.

  ## Examples

      iex> create_comment_vote(%{field: value})
      {:ok, %CommentVote{}}

      iex> create_comment_vote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment_vote(attrs \\ %{}) do
    %CommentVote{}
    |> CommentVote.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a comment_vote.

  ## Examples

      iex> update_comment_vote(comment_vote, %{field: new_value})
      {:ok, %CommentVote{}}

      iex> update_comment_vote(comment_vote, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment_vote(%CommentVote{} = comment_vote, attrs) do
    comment_vote
    |> CommentVote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a comment_vote.

  ## Examples

      iex> delete_comment_vote(comment_vote)
      {:ok, %CommentVote{}}

      iex> delete_comment_vote(comment_vote)
      {:error, %Ecto.Changeset{}}

  """
  def delete_comment_vote(%CommentVote{} = comment_vote) do
    Repo.delete(comment_vote)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment_vote changes.

  ## Examples

      iex> change_comment_vote(comment_vote)
      %Ecto.Changeset{data: %CommentVote{}}

  """
  def change_comment_vote(%CommentVote{} = comment_vote, attrs \\ %{}) do
    CommentVote.changeset(comment_vote, attrs)
  end

  alias Mehungry.Posts.CommentAnswerVote

  @doc """
  Returns the list of comment_answer_votes.

  ## Examples

      iex> list_comment_answer_votes()
      [%CommentAnswerVote{}, ...]

  """
  def list_comment_answer_votes do
    Repo.all(CommentAnswerVote)
  end

  @doc """
  Gets a single comment_answer_vote.

  Raises `Ecto.NoResultsError` if the Comment answer vote does not exist.

  ## Examples

      iex> get_comment_answer_vote!(123)
      %CommentAnswerVote{}

      iex> get_comment_answer_vote!(456)
      ** (Ecto.NoResultsError)

  """
  def get_comment_answer_vote!(id), do: Repo.get!(CommentAnswerVote, id)

  @doc """
  Creates a comment_answer_vote.

  ## Examples

      iex> create_comment_answer_vote(%{field: value})
      {:ok, %CommentAnswerVote{}}

      iex> create_comment_answer_vote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment_answer_vote(attrs \\ %{}) do
    %CommentAnswerVote{}
    |> CommentAnswerVote.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a comment_answer_vote.

  ## Examples

      iex> update_comment_answer_vote(comment_answer_vote, %{field: new_value})
      {:ok, %CommentAnswerVote{}}

      iex> update_comment_answer_vote(comment_answer_vote, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment_answer_vote(%CommentAnswerVote{} = comment_answer_vote, attrs) do
    comment_answer_vote
    |> CommentAnswerVote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a comment_answer_vote.

  ## Examples

      iex> delete_comment_answer_vote(comment_answer_vote)
      {:ok, %CommentAnswerVote{}}

      iex> delete_comment_answer_vote(comment_answer_vote)
      {:error, %Ecto.Changeset{}}

  """
  def delete_comment_answer_vote(%CommentAnswerVote{} = comment_answer_vote) do
    Repo.delete(comment_answer_vote)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment_answer_vote changes.

  ## Examples

      iex> change_comment_answer_vote(comment_answer_vote)
      %Ecto.Changeset{data: %CommentAnswerVote{}}

  """
  def change_comment_answer_vote(%CommentAnswerVote{} = comment_answer_vote, attrs \\ %{}) do
    CommentAnswerVote.changeset(comment_answer_vote, attrs)
  end
end
