defmodule Mehungry.Friends do
  @moduledoc """
  Symmetric friendships built on a request/response flow, mirroring
  `Mehungry.Professionals`' invitation/assignment pattern.

  A `FriendRequest` carries the `pending | accepted | declined` lifecycle; an
  accepted request produces a single normalized `Friendship` row. Friendship is
  the sharing boundary for user-created ingredients (see
  `Mehungry.Food.Ingredients` / `Mehungry.Food.IngredientSearch`), and accepting
  a request also creates a mutual follow so friends surface in each other's feeds.
  """
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserFollow
  alias Mehungry.Users
  alias Mehungry.Friends.{FriendRequest, Friendship}

  # ── Requests ─────────────────────────────────────────────────────────────────

  @doc "Send a friend request from `requester_id` to a user identified by email."
  def send_friend_request_by_email(requester_id, email, message \\ nil) do
    case Accounts.get_user_by_email(email) do
      nil -> {:error, :user_not_found}
      recipient -> send_friend_request(requester_id, recipient.id, message)
    end
  end

  @doc """
  Send a friend request from `requester_id` to `recipient_id`. Guards against
  self-requests, existing friendships, and duplicate pending requests; a
  previously declined request is reset to `pending` and reused.
  """
  def send_friend_request(requester_id, recipient_id, message \\ nil)

  def send_friend_request(requester_id, requester_id, _message), do: {:error, :self}

  def send_friend_request(requester_id, recipient_id, message) do
    if friends?(requester_id, recipient_id) do
      {:error, :already_friends}
    else
      case existing_request(requester_id, recipient_id) do
        %FriendRequest{status: "pending"} ->
          {:error, :already_requested}

        %FriendRequest{} = existing ->
          existing
          |> FriendRequest.changeset(%{status: "pending", message: message})
          |> Repo.update()

        nil ->
          %FriendRequest{}
          |> FriendRequest.changeset(%{
            requester_id: requester_id,
            recipient_id: recipient_id,
            message: message
          })
          |> Repo.insert()
      end
    end
  end

  # Any request between the two users, in either direction.
  defp existing_request(requester_id, recipient_id) do
    Repo.get_by(FriendRequest, requester_id: requester_id, recipient_id: recipient_id)
  end

  def get_friend_request(id), do: Repo.get(FriendRequest, id)

  @doc """
  Accept a pending request (authorized to `recipient_id`). Flips the request to
  `accepted`, creates the normalized `Friendship`, and mutually follows both
  users — all in one transaction.
  """
  def accept_friend_request(request_id, recipient_id) do
    with %FriendRequest{} = req <- Repo.get(FriendRequest, request_id),
         true <- req.recipient_id == recipient_id,
         true <- req.status == "pending" do
      Repo.transaction(fn ->
        {:ok, _req} =
          req |> FriendRequest.changeset(%{status: "accepted"}) |> Repo.update()

        {low, high} = Friendship.normalize(req.requester_id, req.recipient_id)

        {:ok, friendship} =
          %Friendship{}
          |> Friendship.changeset(%{user_low_id: low, user_high_id: high})
          |> Repo.insert()

        ensure_follow(req.requester_id, req.recipient_id)
        ensure_follow(req.recipient_id, req.requester_id)

        friendship
      end)
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  # Follow `follow_id` on behalf of `user_id`, skipping if the row already
  # exists (UserFollow has no unique constraint, so an unguarded insert dups).
  defp ensure_follow(user_id, follow_id) do
    exists? =
      Repo.exists?(
        from f in UserFollow, where: f.user_id == ^user_id and f.follow_id == ^follow_id
      )

    unless exists?, do: Users.save_user_follow(user_id, follow_id)
    :ok
  end

  def decline_friend_request(request_id, recipient_id) do
    with %FriendRequest{} = req <- Repo.get(FriendRequest, request_id),
         true <- req.recipient_id == recipient_id,
         true <- req.status == "pending" do
      req |> FriendRequest.changeset(%{status: "declined"}) |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  @doc "Requester cancels their own pending request (hard delete)."
  def cancel_friend_request(request_id, requester_id) do
    with %FriendRequest{} = req <- Repo.get(FriendRequest, request_id),
         true <- req.requester_id == requester_id,
         true <- req.status == "pending" do
      Repo.delete(req)
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  def list_pending_requests_for(user_id) do
    Repo.all(
      from r in FriendRequest,
        where: r.recipient_id == ^user_id and r.status == "pending",
        order_by: [desc: r.inserted_at],
        preload: [requester: :user_profile]
    )
  end

  def list_sent_requests(user_id) do
    Repo.all(
      from r in FriendRequest,
        where: r.requester_id == ^user_id and r.status == "pending",
        order_by: [desc: r.inserted_at],
        preload: [recipient: :user_profile]
    )
  end

  def count_pending_requests_for(user_id) do
    Repo.one(
      from r in FriendRequest,
        where: r.recipient_id == ^user_id and r.status == "pending",
        select: count(r.id)
    )
  end

  # ── Friendships ────────────────────────────────────────────────────────────────

  @doc "Lists `user_id`'s friends (the other user in each friendship), profile preloaded."
  def list_friends(user_id) do
    Repo.all(
      from f in Friendship,
        where: f.user_low_id == ^user_id or f.user_high_id == ^user_id,
        order_by: [desc: f.inserted_at],
        preload: [user_low: :user_profile, user_high: :user_profile]
    )
    |> Enum.map(fn f ->
      if f.user_low_id == user_id, do: f.user_high, else: f.user_low
    end)
  end

  @doc "The ids of `user_id`'s friends. Drives ingredient-sharing visibility."
  def friend_ids(user_id) do
    Repo.all(
      from f in Friendship,
        where: f.user_low_id == ^user_id or f.user_high_id == ^user_id,
        select: {f.user_low_id, f.user_high_id}
    )
    |> Enum.map(fn {low, high} -> if low == user_id, do: high, else: low end)
  end

  def friends?(user_a_id, user_b_id) do
    {low, high} = Friendship.normalize(user_a_id, user_b_id)
    Repo.exists?(from f in Friendship, where: f.user_low_id == ^low and f.user_high_id == ^high)
  end

  @doc "Ends a friendship (deletes the normalized row). Leaves follows intact."
  def unfriend(user_id, friend_id) do
    {low, high} = Friendship.normalize(user_id, friend_id)

    case Repo.get_by(Friendship, user_low_id: low, user_high_id: high) do
      nil -> {:error, :not_found}
      friendship -> Repo.delete(friendship)
    end
  end
end
