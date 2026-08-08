defmodule Mehungry.Posts do
  alias Mehungry.Posts.CommentVote

  @moduledoc """
  The Posts context.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.Recipe
  alias Mehungry.Posts.Post
  alias Mehungry.Users
  alias Mehungry.Accounts.User

  @doc """
  Returns the list of posts.

  ## Examples

      iex> list_posts()
      [%Post{}, ...]

  """
  def count_user_posts(nil), do: nil

  def count_user_posts(user_id) do
    from(p in Post,
      where: p.user_id == ^user_id,
      select: count(p.id)
    )
    |> Repo.one()
  end

  # The feed grades and re-ranks candidate posts in Elixir, so it can't order in
  # SQL. Instead of loading the whole table on every mount, we cap the candidate
  # set to the most recent N posts and rank within that window. This keeps mount
  # cost (query, preload, grading, socket memory) constant regardless of how many
  # posts exist. Only the fields the feed card actually renders are preloaded.
  @feed_candidate_window 200

  def list_posts(nil) do
    from(p in Post, order_by: [desc: p.inserted_at, desc: p.id], limit: @feed_candidate_window)
    |> Repo.all()
    |> Repo.preload([
      :user,
      reference: [
        :user_recipes,
        :user,
        :comments,
        recipe_hashtags: [:hashtag]
      ]
    ])
  end

  def list_posts(%User{} = user) do
    now = NaiveDateTime.utc_now()
    user_pref_table = Users.calculate_user_pref_table(user)
    follow_ids = Users.list_user_follows(user) |> Enum.map(& &1.follow_id)

    from(p in Post, order_by: [desc: p.inserted_at, desc: p.id], limit: @feed_candidate_window)
    |> Repo.all()
    |> Repo.preload([
      :user,
      reference: [
        :user,
        :user_recipes,
        # Feed card only counts comments; the :user preload is dropped here (it is
        # loaded on the recipe-detail view, not the feed).
        :comments,
        recipe_hashtags: [:hashtag],
        recipe_ingredients: [ingredient: [:category]]
      ]
    ])
    |> Enum.map(fn x ->
      grading_score = Users.calculate_recipe_grading(x.reference, user_pref_table, follow_ids)
      recency_hours = NaiveDateTime.diff(now, x.inserted_at, :second) / 3600.0
      recency_score = :math.exp(-recency_hours / 96.0) * 3.0
      {x, recency_score + grading_score}
    end)
    |> Enum.sort_by(fn {_x, score} -> score end, :desc)
    |> Enum.map(fn {x, _score} -> x end)
  end

  # For each recipe, prefer the post whose language_name matches the user's language.
  # Falls back to the first post for that recipe (original language) if no translation post exists.
  # Also applies recipe_translations to post.reference so the recipe title is in the user's language.
  def localize_for_language(posts, nil), do: posts

  def localize_for_language(posts, language_name) do
    # Pick best post per reference_id, preserving score-based order
    selected_by_ref =
      posts
      |> Enum.group_by(& &1.reference_id)
      |> Map.new(fn {ref_id, group} ->
        best = Enum.find(group, List.first(group), &(&1.language_name == language_name))
        {ref_id, best}
      end)

    selected =
      posts
      |> Enum.uniq_by(& &1.reference_id)
      |> Enum.map(&Map.get(selected_by_ref, &1.reference_id))
      |> Enum.reject(&is_nil/1)

    recipe_ids = selected |> Enum.map(& &1.reference_id) |> Enum.reject(&is_nil/1)
    translations = Mehungry.Food.load_recipe_translations_map(recipe_ids, language_name)

    Enum.map(selected, fn post ->
      case {post.reference, Map.get(translations, post.reference_id)} do
        {nil, _} ->
          post

        {_, nil} ->
          post

        {ref, translation} ->
          %{post | reference: Mehungry.Food.apply_recipe_translation(ref, translation)}
      end
    end)
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

  #      comments: [:user, votes: [:user], comment_answers: [:user, votes: [:user]]]

  def get_post!(id) do
    Repo.get!(Post, id)
    |> Repo.preload([
      :user,
      :upvotes,
      :downvotes,
      reference: [
        :user,
        :user_recipes,
        :recipe_hashtags,
        recipe_ingredients: [:ingredient],
        comments: [:user]
      ]
    ])
  end

  def subscribe_to_recipe(%{recipe_id: recipe_id}) do
    Phoenix.PubSub.subscribe(Mehungry.PubSub, "recipe:" <> to_string(recipe_id))
  end

  defp broadcast_change({:ok, comment}) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, "recipe:" <> to_string(comment.recipe_id), %{
      new_comment: comment
    })

    {:ok, comment}
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

  defp broadcast_comment_vote({:ok, comment}, type_) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, "recipe:" <> to_string(comment.recipe_id), %{
      new_comment_vote: comment,
      type_: type_
    })

    {:ok, comment}
  end

  @doc """
  Creates a post.

  ## Examples

  iex> create_post(%{field: value})
  {:ok, %Post{}}

  iex> create_post(%{field: bad_value})
  {:error, %Ecto.Changeset{}}

  """
  def create_post(%Recipe{} = recipe) do
    attrs =
      %{
        reference_id: recipe.id,
        md_media_url: recipe.image_url,
        user_id: recipe.user_id,
        title: recipe.title,
        type_: "RECIPE"
      }

    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def create_post_for_translation(%Recipe{} = recipe, translation) do
    attrs = %{
      reference_id: recipe.id,
      md_media_url: recipe.image_url,
      user_id: recipe.user_id,
      title: translation.title,
      language_name: translation.language_name,
      type_: "RECIPE"
    }

    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def post_exists_for?(recipe_id, nil) do
    from(p in Post, where: p.reference_id == ^recipe_id and is_nil(p.language_name))
    |> Repo.exists?()
  end

  def post_exists_for?(recipe_id, language_name) do
    from(p in Post, where: p.reference_id == ^recipe_id and p.language_name == ^language_name)
    |> Repo.exists?()
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

  def count_user_comments(nil), do: nil

  def count_user_comments(user_id) do
    from(c in Comment,
      where: c.user_id == ^user_id,
      select: count(c.id)
    )
    |> Repo.one()
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
    |> Repo.preload([:user, comment_answers: [:user, votes: [:user]], votes: [:user]])
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
      {:ok, _comment} ->
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

      {:error, _} ->
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
    from(c in CommentVote,
      where: c.user_id == ^user_id and c.comment_id == ^comment_id
    )
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

    if not is_nil(vote) and vote.positive != reaction do
      update_comment_vote(vote, %{positive: get_positive.(reaction)})
      broadcast_comment_vote({:ok, comment}, "vote")
    else
      %CommentVote{}
      |> CommentVote.changeset(%{user_id: user_id, comment_id: comment_id, positive: reaction})
      |> Repo.insert()

      broadcast_comment_vote({:ok, comment}, "vote")
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
