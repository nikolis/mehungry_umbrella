defmodule Mehungry.Accounts.Admin do
  @moduledoc """
  Administrative user operations: lookups, filtered listings, account
  deletion with full data cascade, and Gmail-alias dedupe.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo
  alias Mehungry.Accounts.User

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by the canonicalized form of an email, so that any Gmail-style
  alias of a registered address resolves to the same account.
  """
  def get_user_by_canonical_email(email) when is_binary(email) do
    Repo.get_by(User, canonical_email: User.canonical_email(email))
  end

  @doc """
  Gets a single user. Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Lists users, newest first, optionally filtered. `filters` is a string-keyed
  map (as sent by a LiveView form):

    * `"confirmation"` — `"confirmed"` | `"unconfirmed"` | anything else = all
    * `"registered"`   — `"7d"` | `"30d"` | `"90d"` (registration recency) | else all
    * `"q"`            — case-insensitive substring match on email or name

  The `activity` (has-recipes) filter is applied in the caller, since it needs
  the per-user recipe counts (see `Mehungry.Food.recipe_counts_by_user_id/0`).
  """
  def list_users(filters \\ %{}) do
    User
    |> filter_confirmation(filters["confirmation"])
    |> filter_registered(filters["registered"])
    |> filter_user_query(filters["q"])
    |> order_by([u], desc: u.inserted_at)
    |> Repo.all()
  end

  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  defp filter_confirmation(query, "confirmed"),
    do: where(query, [u], not is_nil(u.confirmed_at))

  defp filter_confirmation(query, "unconfirmed"),
    do: where(query, [u], is_nil(u.confirmed_at))

  defp filter_confirmation(query, _), do: query

  defp filter_registered(query, period) when period in ["7d", "30d", "90d"] do
    days = %{"7d" => 7, "30d" => 30, "90d" => 90}[period]
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)
    where(query, [u], u.inserted_at >= ^cutoff)
  end

  defp filter_registered(query, _), do: query

  defp filter_user_query(query, q) when is_binary(q) do
    case String.trim(q) do
      "" ->
        query

      term ->
        like = "%#{term}%"
        where(query, [u], ilike(u.email, ^like) or ilike(u.name, ^like))
    end
  end

  defp filter_user_query(query, _), do: query

  @doc """
  Finds accounts that share a canonical email (Gmail-alias clusters) and, for
  each cluster of more than one, keeps the oldest account and deletes the rest
  via `delete_user/1` (which cascades through the user's data).

  Options:

    * `:dry_run` (default `true`) — when true, nothing is deleted; the function
      only computes and returns what *would* happen.

  Returns `%{clusters: n, kept: [ids], deleted: [%{id, email, canonical_email}], dry_run: bool}`.
  """
  def dedupe_alias_accounts(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, true)

    clusters =
      from(u in User,
        where: not is_nil(u.canonical_email),
        order_by: [asc: u.inserted_at, asc: u.id],
        select: %{id: u.id, email: u.email, canonical_email: u.canonical_email}
      )
      |> Repo.all()
      |> Enum.group_by(& &1.canonical_email)
      |> Enum.filter(fn {_canonical, members} -> length(members) > 1 end)

    {kept, to_delete} =
      Enum.reduce(clusters, {[], []}, fn {_canonical, [keep | rest]}, {kept, del} ->
        {[keep.id | kept], del ++ rest}
      end)

    unless dry_run, do: Enum.each(to_delete, &delete_alias_account/1)

    %{
      clusters: length(clusters),
      kept: kept,
      deleted: to_delete,
      dry_run: dry_run
    }
  end

  defp delete_alias_account(%{id: id, email: email, canonical_email: canonical}) do
    Logger.warning(
      "[dedupe_alias_accounts] deleting user id=#{id} email=#{email} canonical=#{canonical}"
    )

    case Repo.get(User, id) do
      nil -> :ok
      user -> delete_user(user)
    end
  end

  def delete_user(%User{} = user) do
    uid = user.id

    # Collect all recipe IDs owned by the user
    recipe_ids =
      Repo.all(from r in Mehungry.Food.Recipe, where: r.user_id == ^uid, select: r.id)

    # Collect all comment IDs: comments on user's recipes (by anyone) + comments made by user
    comment_ids_on_recipes =
      Repo.all(from c in Mehungry.Posts.Comment, where: c.recipe_id in ^recipe_ids, select: c.id)

    user_comment_ids =
      Repo.all(from c in Mehungry.Posts.Comment, where: c.user_id == ^uid, select: c.id)

    all_comment_ids = Enum.uniq(comment_ids_on_recipes ++ user_comment_ids)

    # Collect all comment answer IDs on those comments
    all_answer_ids =
      Repo.all(
        from ca in Mehungry.Posts.CommentAnswer,
          where: ca.comment_id in ^all_comment_ids or ca.user_id == ^uid,
          select: ca.id
      )

    # Delete leaf nodes first, then work up the dependency tree

    # CommentAnswerVotes (depend on comment_answers and users)
    Repo.delete_all(
      from v in Mehungry.Posts.CommentAnswerVote,
        where: v.comment_answer_id in ^all_answer_ids or v.user_id == ^uid
    )

    # CommentVotes (depend on comments and users)
    Repo.delete_all(
      from v in Mehungry.Posts.CommentVote,
        where: v.comment_id in ^all_comment_ids or v.user_id == ^uid
    )

    # CommentAnswers (depend on comments and users)
    Repo.delete_all(
      from ca in Mehungry.Posts.CommentAnswer,
        where: ca.comment_id in ^all_comment_ids or ca.user_id == ^uid
    )

    # All comments (on user's recipes and by the user)
    Repo.delete_all(
      from c in Mehungry.Posts.Comment,
        where: c.recipe_id in ^recipe_ids or c.user_id == ^uid
    )

    # RecipeIngredients
    Repo.delete_all(from ri in Mehungry.Food.RecipeIngredient, where: ri.recipe_id in ^recipe_ids)

    # Recipes
    Repo.delete_all(from r in Mehungry.Food.Recipe, where: r.user_id == ^uid)

    # UserMeals (recipe_user_meals and ingredient_user_meals cascade via :delete_all)
    Repo.delete_all(from u_m in Mehungry.History.UserMeal, where: u_m.user_id == ^uid)

    # ShoppingBaskets and their items
    basket_ids =
      Repo.all(
        from b in Mehungry.Inventory.ShoppingBasket, where: b.user_id == ^uid, select: b.id
      )

    Repo.delete_all(
      from bi in Mehungry.Inventory.BasketIngredient, where: bi.shopping_basket_id in ^basket_ids
    )

    Repo.delete_all(from b in Mehungry.Inventory.ShoppingBasket, where: b.user_id == ^uid)

    # UserProfile (cascades to user_category_rules and user_ingredient_rules via user_profile_id)
    Repo.delete_all(from p in Mehungry.Accounts.UserProfile, where: p.user_id == ^uid)

    # PostUpvotes and PostDownvotes by the user (post_id references, not comment_id)
    Repo.delete_all(from v in Mehungry.Posts.PostUpvote, where: v.user_id == ^uid)
    Repo.delete_all(from v in Mehungry.Posts.PostDownvote, where: v.user_id == ^uid)

    # Delete the user — tokens, credentials, posts, user_recipes, follows (new table),
    # social_media_posts, subscriptions, ai_usage all cascade via :delete_all
    Repo.delete(user)
  end
end
