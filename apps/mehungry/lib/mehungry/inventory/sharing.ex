defmodule Mehungry.Inventory.Sharing do
  @moduledoc """
  Sharing a shopping list: invitations and members.

  The list's **owner** (`shopping_baskets.user_id`) invites people; an accepted
  invitation becomes a `BasketMember`. Members read the list and change its
  items; only the owner renames or deletes it, invites, revokes and removes.

  An invitation is a **single-use link** that expires after 7 days. It may be
  addressed to an email: when that email belongs to an existing account the
  invitee also gets an in-app notification and can answer without the link.
  Whoever is signed in when the link is opened is the one who joins.

  Rules enforced here (every client goes through this module):

    * the inviter must own the list and have a confirmed email;
    * at most 6 people per list (owner included) and 10 pending invitations;
    * a per-inviter rate limit;
    * a block between the two users (either direction) silently suppresses
      delivery and makes the invitation unusable by that user.

  Public functions are also exposed on the `Mehungry.Inventory` facade. See
  `docs/features/shared_basket.md`.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Accounts.User
  alias Mehungry.Inventory
  alias Mehungry.Inventory.{BasketInvitation, BasketMember, ShoppingBasket}
  alias Mehungry.Moderation
  alias Mehungry.Notifications
  alias Mehungry.RateLimit
  alias Mehungry.Repo

  @max_people 6
  @max_pending 10
  @ttl_days 7
  @invites_per_hour 20

  @doc "Most people a list can have, owner included."
  def max_people, do: @max_people

  # ── Inviting ─────────────────────────────────────────────────────────────

  @doc """
  Creates an invitation to the inviter's own basket.

  `opts` may carry `:email` (or `"email"`). Returns `{:ok, invitation, token}`;
  `token` is the raw link token, available **only here** (its hash is what is
  stored), so the caller must build and hand out the link now.

  The result is the same whether or not the email belongs to an account, so the
  form cannot be used to probe for registered emails.

  Errors: `:not_found` (not the owner), `:email_not_confirmed`, `:rate_limited`,
  `:basket_full`, `:too_many_pending`, `:invalid_email`, `:cannot_invite_yourself`,
  `:already_member`.
  """
  def invite(%User{} = inviter, basket_id, opts \\ %{}) do
    email = normalize_email(opts[:email] || opts["email"])

    with %ShoppingBasket{} = basket <- owned_basket(inviter.id, basket_id),
         :ok <- confirmed(inviter),
         :ok <- valid_email(email),
         :ok <- RateLimit.hit("basket_invite:#{inviter.id}", @invites_per_hour, 3_600_000),
         :ok <- room_for_invite(basket),
         invitee = find_invitee(email),
         :ok <- not_self(inviter, invitee),
         :ok <- not_member(basket, invitee) do
      # A blocked pair never hears from each other: keep the row (so the inviter
      # sees the same outcome) but do not address or deliver it.
      invitee = if blocked_pair?(inviter, invitee), do: nil, else: invitee
      token = generate_token()

      result =
        %BasketInvitation{}
        |> BasketInvitation.changeset(%{
          shopping_basket_id: basket.id,
          inviter_id: inviter.id,
          invitee_email: email,
          invitee_user_id: invitee && invitee.id,
          token_hash: hash_token(token),
          expires_at: expiry()
        })
        |> Repo.insert()

      with {:ok, invitation} <- result do
        notify_invitee(invitation, basket, inviter, invitee)
        Inventory.broadcast_change(basket.id)
        {:ok, invitation, token}
      end
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp notify_invitee(_invitation, _basket, _inviter, nil), do: :ok

  defp notify_invitee(invitation, basket, inviter, %User{} = invitee) do
    Notifications.emit(invitee.id, "basket_invitation",
      actor_id: inviter.id,
      subject_type: "basket_invitation",
      subject_id: invitation.id,
      data: %{"basket_title" => basket.title, "invitation_id" => invitation.id}
    )

    :ok
  end

  @doc """
  Whether an invitation addressed to an email should also be **emailed**. False
  when the address belongs to someone in a block relationship with the inviter.
  """
  def email_deliverable?(%BasketInvitation{invitee_email: nil}), do: false

  def email_deliverable?(%BasketInvitation{invitee_email: email, inviter_id: inviter_id}) do
    case find_invitee(email) do
      nil -> true
      %User{} = invitee -> not blocked_pair?(%User{id: inviter_id}, invitee)
    end
  end

  # ── Answering ────────────────────────────────────────────────────────────

  @doc """
  What an invitee may see **before** accepting: who invited them and the list's
  title, never its contents. `{:ok, %{invitation:, basket_title:, inviter_name:}}`
  or `{:error, :invalid}` for an unknown, used, revoked or expired link.
  """
  def preview_invitation(token) when is_binary(token) do
    case usable_by_token(token) do
      nil ->
        {:error, :invalid}

      invitation ->
        invitation = Repo.preload(invitation, [:shopping_basket, inviter: :user_profile])

        {:ok,
         %{
           invitation: invitation,
           basket_title: invitation.shopping_basket.title,
           inviter_name: display_name(invitation.inviter)
         }}
    end
  end

  def preview_invitation(_), do: {:error, :invalid}

  @doc """
  Accepts the invitation behind a link token as `user`. Returns `{:ok, basket}`
  (also when the user already has access, in which case the link is not used
  up), or `{:error, :invalid | :basket_full}`.
  """
  def accept_by_token(%User{} = user, token) when is_binary(token) do
    case usable_by_token(token) do
      nil -> {:error, :invalid}
      invitation -> do_accept(user, invitation.id)
    end
  end

  def accept_by_token(_user, _token), do: {:error, :invalid}

  @doc """
  Accepts an invitation that was addressed to `user` (the in-app path, no
  token). `{:error, :invalid}` unless it is theirs, pending and unexpired.
  """
  def accept(%User{} = user, invitation_id) do
    case addressed_to(user.id, invitation_id) do
      nil -> {:error, :invalid}
      invitation -> do_accept(user, invitation.id)
    end
  end

  @doc "Declines an invitation addressed to `user`. The inviter is not told."
  def decline(%User{} = user, invitation_id) do
    case addressed_to(user.id, invitation_id) do
      nil ->
        {:error, :invalid}

      invitation ->
        {:ok, _} = invitation |> Ecto.Changeset.change(status: "declined") |> Repo.update()
        Inventory.broadcast_change(invitation.shopping_basket_id)
        :ok
    end
  end

  # Runs in a transaction with the invitation row locked, so one link can never
  # admit two people and the size limit holds under concurrent accepts.
  defp do_accept(%User{} = user, invitation_id) do
    fn -> locked_accept(user, invitation_id) end
    |> Repo.transaction()
    |> case do
      {:ok, {basket, :already_on_list}} ->
        {:ok, basket}

      {:ok, {basket, :joined}} ->
        Notifications.emit(basket.user_id, "basket_joined",
          actor_id: user.id,
          subject_type: "basket",
          subject_id: basket.id,
          data: %{"basket_title" => basket.title}
        )

        Inventory.broadcast_change(basket.id)
        {:ok, basket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp locked_accept(user, invitation_id) do
    invitation =
      from(i in BasketInvitation, where: i.id == ^invitation_id, lock: "FOR UPDATE")
      |> Repo.one()

    # Locking the basket too serializes accepts of *different* invitations to
    # the same list, so the size limit cannot be overshot.
    basket =
      invitation &&
        Repo.one(
          from s in ShoppingBasket,
            where: s.id == ^invitation.shopping_basket_id,
            lock: "FOR UPDATE"
        )

    case accept_check(user, invitation, basket) do
      :ok ->
        admit(user, invitation, basket)
        {basket, :joined}

      # Already on the list: nothing to do, and the link stays usable.
      :already_on_list ->
        {basket, :already_on_list}

      {:refuse, reason} ->
        Repo.rollback(reason)
    end
  end

  defp accept_check(_user, nil, _basket), do: {:refuse, :invalid}
  defp accept_check(_user, _invitation, nil), do: {:refuse, :invalid}

  defp accept_check(user, invitation, basket) do
    cond do
      not usable?(invitation) -> {:refuse, :invalid}
      Inventory.basket_role(basket.id, user.id) != nil -> :already_on_list
      blocked_pair?(user, %User{id: basket.user_id}) -> {:refuse, :invalid}
      people_count(basket.id) >= @max_people -> {:refuse, :basket_full}
      true -> :ok
    end
  end

  defp admit(user, invitation, basket) do
    {:ok, _member} =
      %BasketMember{}
      |> BasketMember.changeset(%{
        shopping_basket_id: basket.id,
        user_id: user.id,
        invited_by_id: invitation.inviter_id
      })
      |> Repo.insert(on_conflict: :nothing)

    {:ok, _} =
      invitation
      |> Ecto.Changeset.change(status: "accepted", accepted_by_id: user.id)
      |> Repo.update()

    :ok
  end

  # ── Owner management ─────────────────────────────────────────────────────

  @doc "Revokes a pending invitation on the owner's basket. `:ok | {:error, :not_found}`."
  def revoke(%User{} = owner, basket_id, invitation_id) do
    with %ShoppingBasket{} = basket <- owned_basket(owner.id, basket_id),
         %BasketInvitation{} = invitation <-
           Repo.get_by(BasketInvitation,
             id: invitation_id,
             shopping_basket_id: basket.id,
             status: "pending"
           ) do
      {:ok, _} = invitation |> Ecto.Changeset.change(status: "revoked") |> Repo.update()
      Inventory.broadcast_change(basket.id)
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "A basket's pending, unexpired invitations (the owner's Share view), newest first."
  def list_pending(basket_id) do
    from(i in BasketInvitation,
      where: i.shopping_basket_id == ^basket_id and i.status == "pending",
      where: i.expires_at > ^now(),
      order_by: [desc: i.id]
    )
    |> Repo.all()
  end

  @doc """
  Pending, unexpired invitations addressed to `user_id`, newest first, with the
  basket and inviter preloaded (render only the basket's title).
  """
  def list_for_user(user_id) do
    from(i in BasketInvitation,
      where: i.invitee_user_id == ^user_id and i.status == "pending",
      where: i.expires_at > ^now(),
      order_by: [desc: i.id],
      preload: [:shopping_basket, inviter: :user_profile]
    )
    |> Repo.all()
  end

  @doc """
  Removes `user_id` from a basket. The owner may remove anyone; a member may
  remove only themselves (leaving). The owner cannot be removed.
  `:ok | {:error, :not_found | :forbidden}`.
  """
  def remove_member(%User{} = actor, basket_id, user_id) do
    basket = Repo.get(ShoppingBasket, basket_id)

    cond do
      is_nil(basket) -> {:error, :not_found}
      basket.user_id != actor.id and actor.id != user_id -> {:error, :forbidden}
      true -> delete_member(basket.id, user_id)
    end
  end

  defp delete_member(basket_id, user_id) do
    {count, _} =
      from(m in BasketMember, where: m.shopping_basket_id == ^basket_id and m.user_id == ^user_id)
      |> Repo.delete_all()

    if count > 0 do
      Inventory.broadcast_change(basket_id)
      :ok
    else
      {:error, :not_found}
    end
  end

  # ── People on a list ─────────────────────────────────────────────────────

  @doc """
  Everyone on a loaded basket, owner first:
  `[%{id:, name:, avatar_url:, role: :owner | :member}]`. `name` is the profile
  alias or account name and may be `nil`; an email is never exposed.
  """
  def people(%ShoppingBasket{} = basket) do
    owner =
      case basket.user do
        %User{} = user -> [person(user, :owner)]
        _ -> []
      end

    members =
      case basket.members do
        members when is_list(members) ->
          members
          |> Enum.sort_by(& &1.id)
          |> Enum.flat_map(fn
            %{user: %User{} = user} -> [person(user, :member)]
            _ -> []
          end)

        _ ->
          []
      end

    owner ++ members
  end

  defp person(%User{} = user, role) do
    %{id: user.id, name: display_name(user), avatar_url: user.profile_pic, role: role}
  end

  @doc "A user's public name (profile alias, else account name), or `nil`. Never the email."
  def display_name(%User{} = user) do
    user = Repo.preload(user, :user_profile)

    alias_name =
      case user.user_profile do
        %{alias: name} when is_binary(name) and name != "" -> name
        _ -> nil
      end

    alias_name || non_blank(user.name)
  end

  def display_name(_), do: nil

  defp non_blank(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp non_blank(_), do: nil

  # ── Lifecycle hooks called by other contexts ─────────────────────────────

  @doc """
  Called when one user blocks another: neither stays on a list the other owns,
  and pending invitations between them are revoked.
  """
  def handle_block(user_a_id, user_b_id) do
    pairs = [{user_a_id, user_b_id}, {user_b_id, user_a_id}]

    for {owner_id, member_id} <- pairs do
      basket_ids =
        Repo.all(from s in ShoppingBasket, where: s.user_id == ^owner_id, select: s.id)

      {removed, _} =
        from(m in BasketMember,
          where: m.shopping_basket_id in ^basket_ids and m.user_id == ^member_id
        )
        |> Repo.delete_all()

      {revoked, _} =
        from(i in BasketInvitation,
          where:
            i.inviter_id == ^owner_id and i.invitee_user_id == ^member_id and
              i.status == "pending"
        )
        |> Repo.update_all(set: [status: "revoked"])

      if removed + revoked > 0, do: Enum.each(basket_ids, &Inventory.broadcast_change/1)
    end

    :ok
  end

  @doc """
  Called before an account is deleted: each list the user owns **and shares**
  is handed to its longest-standing member, so deleting an account never takes
  other people's shared list away. Lists with no members are left for the
  caller to delete. Returns the ids of the transferred baskets.
  """
  def transfer_shared_baskets(user_id) do
    shared =
      Repo.all(
        from s in ShoppingBasket,
          where: s.user_id == ^user_id,
          join: m in BasketMember,
          on: m.shopping_basket_id == s.id,
          distinct: s.id,
          select: s.id
      )

    Enum.map(shared, fn basket_id ->
      {:ok, _} =
        Repo.transaction(fn ->
          heir =
            from(m in BasketMember,
              where: m.shopping_basket_id == ^basket_id,
              order_by: [asc: m.inserted_at, asc: m.id],
              limit: 1
            )
            |> Repo.one!()

          Repo.delete!(heir)

          from(s in ShoppingBasket, where: s.id == ^basket_id)
          |> Repo.update_all(set: [user_id: heir.user_id])

          # The old owner's unanswered invitations die with their account.
          from(i in BasketInvitation,
            where: i.shopping_basket_id == ^basket_id and i.status == "pending"
          )
          |> Repo.update_all(set: [status: "revoked"])
        end)

      Inventory.broadcast_change(basket_id)
      basket_id
    end)
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp owned_basket(user_id, basket_id) do
    Repo.one(from s in ShoppingBasket, where: s.id == ^basket_id and s.user_id == ^user_id)
  end

  defp confirmed(%User{confirmed_at: nil}), do: {:error, :email_not_confirmed}
  defp confirmed(%User{}), do: :ok

  # Kept as typed (trimmed, lower-cased) so the owner recognises it in the
  # pending list; matching it to an account uses the canonical form.
  defp normalize_email(email) when is_binary(email) do
    case String.trim(email) do
      "" -> nil
      trimmed -> String.downcase(trimmed)
    end
  end

  defp normalize_email(_), do: nil

  defp valid_email(nil), do: :ok

  defp valid_email(email) do
    if String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) and byte_size(email) <= 160,
      do: :ok,
      else: {:error, :invalid_email}
  end

  defp find_invitee(nil), do: nil
  defp find_invitee(email), do: Repo.get_by(User, canonical_email: User.canonical_email(email))

  defp not_self(%User{id: id}, %User{id: id}), do: {:error, :cannot_invite_yourself}
  defp not_self(_inviter, _invitee), do: :ok

  defp not_member(_basket, nil), do: :ok

  defp not_member(basket, %User{id: user_id}) do
    if Inventory.basket_role(basket.id, user_id), do: {:error, :already_member}, else: :ok
  end

  defp room_for_invite(basket) do
    cond do
      people_count(basket.id) >= @max_people -> {:error, :basket_full}
      length(list_pending(basket.id)) >= @max_pending -> {:error, :too_many_pending}
      true -> :ok
    end
  end

  # Owner + members.
  defp people_count(basket_id) do
    1 + Repo.aggregate(from(m in BasketMember, where: m.shopping_basket_id == ^basket_id), :count)
  end

  defp blocked_pair?(_user, nil), do: false

  defp blocked_pair?(%User{} = a, %User{} = b) do
    Moderation.blocked?(a, b.id) or Moderation.blocked?(b, a.id)
  end

  defp usable_by_token(token) do
    case Repo.get_by(BasketInvitation, token_hash: hash_token(token)) do
      %BasketInvitation{} = invitation -> if usable?(invitation), do: invitation
      nil -> nil
    end
  end

  defp addressed_to(user_id, invitation_id) do
    case Repo.get_by(BasketInvitation, id: invitation_id, invitee_user_id: user_id) do
      %BasketInvitation{} = invitation -> if usable?(invitation), do: invitation
      nil -> nil
    end
  end

  defp usable?(%BasketInvitation{status: "pending", expires_at: expires_at}),
    do: DateTime.compare(expires_at, now()) == :gt

  defp usable?(_), do: false

  defp generate_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  defp hash_token(token), do: :crypto.hash(:sha256, token)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp expiry, do: DateTime.add(now(), @ttl_days * 86_400, :second)
end
