defmodule Mehungry.Inventory.SharingTest do
  use Mehungry.DataCase

  alias Mehungry.Accounts
  alias Mehungry.AccountsFixtures
  alias Mehungry.Inventory
  alias Mehungry.Inventory.{BasketInvitation, Sharing}
  alias Mehungry.Moderation
  alias Mehungry.Notifications
  alias Mehungry.Repo

  defp confirmed_user do
    user = AccountsFixtures.user_fixture()
    {:ok, %{user: user}} = Repo.transaction(Accounts.confirm_user_multi(user))
    user
  end

  defp basket_for(user, title \\ "Weekly groceries") do
    {:ok, basket} = Inventory.create_shopping_basket(%{user_id: user.id, title: title})
    basket
  end

  # Invites by link and has `member` accept it.
  defp share!(owner, basket, member) do
    {:ok, _invitation, token} = Sharing.invite(owner, basket.id)
    {:ok, _basket} = Sharing.accept_by_token(member, token)
    :ok
  end

  setup do
    owner = confirmed_user()
    %{owner: owner, basket: basket_for(owner), friend: confirmed_user()}
  end

  describe "invite/3" do
    test "creates a pending single-use link invitation", %{owner: owner, basket: basket} do
      assert {:ok, %BasketInvitation{status: "pending"} = invitation, token} =
               Sharing.invite(owner, basket.id)

      assert is_binary(token)
      assert invitation.invitee_email == nil
      # Only the hash is stored.
      refute invitation.token_hash == token
      assert [%{id: id}] = Sharing.list_pending(basket.id)
      assert id == invitation.id
    end

    test "addressing a registered email notifies that user", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      assert {:ok, invitation, _token} = Sharing.invite(owner, basket.id, %{email: friend.email})
      assert invitation.invitee_user_id == friend.id

      assert [%{type: "basket_invitation", actor_id: actor_id, data: data}] =
               Notifications.list(friend.id)

      assert actor_id == owner.id
      assert data["basket_title"] == "Weekly groceries"
      assert [%{id: id}] = Sharing.list_for_user(friend.id)
      assert id == invitation.id
    end

    test "an unregistered email gets the same outcome", %{owner: owner, basket: basket} do
      assert {:ok, invitation, token} =
               Sharing.invite(owner, basket.id, %{"email" => "nobody@example.com"})

      assert is_binary(token)
      assert invitation.invitee_user_id == nil
      assert invitation.invitee_email == "nobody@example.com"
      assert Sharing.email_deliverable?(invitation)
    end

    test "only the owner can invite", %{basket: basket, friend: friend} do
      assert {:error, :not_found} = Sharing.invite(friend, basket.id)
    end

    test "a member cannot invite", %{owner: owner, basket: basket, friend: friend} do
      share!(owner, basket, friend)
      assert {:error, :not_found} = Sharing.invite(friend, basket.id)
    end

    test "requires a confirmed email", %{} do
      unconfirmed = AccountsFixtures.user_fixture()
      basket = basket_for(unconfirmed)
      assert {:error, :email_not_confirmed} = Sharing.invite(unconfirmed, basket.id)
    end

    test "rejects a malformed email, yourself, and an existing member", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      assert {:error, :invalid_email} = Sharing.invite(owner, basket.id, %{email: "not-an-email"})

      assert {:error, :cannot_invite_yourself} =
               Sharing.invite(owner, basket.id, %{email: owner.email})

      share!(owner, basket, friend)
      assert {:error, :already_member} = Sharing.invite(owner, basket.id, %{email: friend.email})
    end

    test "a blocked pair is not addressed, notified or emailed", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      :ok = Moderation.block_user(friend, owner.id)

      assert {:ok, invitation, token} = Sharing.invite(owner, basket.id, %{email: friend.email})
      assert invitation.invitee_user_id == nil
      refute Sharing.email_deliverable?(invitation)
      assert Notifications.list(friend.id) == []
      # ...and the link does not let the blocker in either.
      assert {:error, :invalid} = Sharing.accept_by_token(friend, token)
    end

    test "caps pending invitations per list", %{owner: owner, basket: basket} do
      for _ <- 1..10, do: {:ok, _, _} = Sharing.invite(owner, basket.id)
      assert {:error, :too_many_pending} = Sharing.invite(owner, basket.id)
    end
  end

  describe "accepting" do
    test "preview shows only the inviter and the title", %{owner: owner, basket: basket} do
      {:ok, _, token} = Sharing.invite(owner, basket.id)

      assert {:ok, %{basket_title: "Weekly groceries"} = preview} =
               Sharing.preview_invitation(token)

      assert Map.keys(preview) |> Enum.sort() == [:basket_title, :invitation, :inviter_name]
      assert {:error, :invalid} = Sharing.preview_invitation("nope")
    end

    test "accepting by link makes the user a member and tells the owner", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      {:ok, _, token} = Sharing.invite(owner, basket.id)
      assert {:ok, accepted} = Sharing.accept_by_token(friend, token)
      assert accepted.id == basket.id

      assert Inventory.basket_role(basket.id, friend.id) == :member
      assert Inventory.get_accessible_basket(friend.id, basket.id)
      assert [%{type: "basket_joined", actor_id: actor_id}] = Notifications.list(owner.id)
      assert actor_id == friend.id
      assert Sharing.list_pending(basket.id) == []
    end

    test "a link is single-use", %{owner: owner, basket: basket, friend: friend} do
      {:ok, _, token} = Sharing.invite(owner, basket.id)
      {:ok, _} = Sharing.accept_by_token(friend, token)

      assert {:error, :invalid} = Sharing.accept_by_token(confirmed_user(), token)
      assert {:error, :invalid} = Sharing.preview_invitation(token)
    end

    test "an expired or revoked link is refused", %{owner: owner, basket: basket, friend: friend} do
      {:ok, invitation, token} = Sharing.invite(owner, basket.id)

      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      invitation |> Ecto.Changeset.change(expires_at: past) |> Repo.update!()
      assert {:error, :invalid} = Sharing.accept_by_token(friend, token)

      {:ok, revoked, revoked_token} = Sharing.invite(owner, basket.id)
      assert :ok = Sharing.revoke(owner, basket.id, revoked.id)
      assert {:error, :invalid} = Sharing.accept_by_token(friend, revoked_token)
      assert Inventory.basket_role(basket.id, friend.id) == nil
    end

    test "someone already on the list does not use the link up", %{owner: owner, basket: basket} do
      {:ok, _, token} = Sharing.invite(owner, basket.id)
      assert {:ok, _} = Sharing.accept_by_token(owner, token)
      assert {:ok, _} = Sharing.preview_invitation(token)
    end

    test "the in-app path works only for the addressed user", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      {:ok, invitation, _} = Sharing.invite(owner, basket.id, %{email: friend.email})

      assert {:error, :invalid} = Sharing.accept(confirmed_user(), invitation.id)
      assert {:ok, _} = Sharing.accept(friend, invitation.id)
      assert Inventory.basket_role(basket.id, friend.id) == :member
    end

    test "declining is silent and final", %{owner: owner, basket: basket, friend: friend} do
      {:ok, invitation, token} = Sharing.invite(owner, basket.id, %{email: friend.email})

      assert :ok = Sharing.decline(friend, invitation.id)
      assert Notifications.list(owner.id) == []
      assert {:error, :invalid} = Sharing.accept_by_token(friend, token)
      assert Sharing.list_for_user(friend.id) == []
    end

    test "a list holds at most #{Sharing.max_people()} people", %{owner: owner, basket: basket} do
      for _ <- 2..Sharing.max_people(), do: share!(owner, basket, confirmed_user())

      assert {:error, :basket_full} = Sharing.invite(owner, basket.id)
    end
  end

  describe "access" do
    setup %{owner: owner, basket: basket, friend: friend} do
      share!(owner, basket, friend)
      :ok
    end

    test "a member sees the shared list among their lists", %{basket: basket, friend: friend} do
      own = basket_for(friend, "Mine")
      ids = friend.id |> Inventory.list_shopping_baskets_for_user() |> Enum.map(& &1.id)
      assert Enum.sort(ids) == Enum.sort([basket.id, own.id])
    end

    test "a member reads the list but does not own it", %{basket: basket, friend: friend} do
      assert %{} = Inventory.get_accessible_basket(friend.id, basket.id)
      assert Inventory.get_user_shopping_basket(friend.id, basket.id) == nil
    end

    test "a stranger has no access", %{basket: basket} do
      stranger = confirmed_user()
      assert Inventory.get_accessible_basket(stranger.id, basket.id) == nil
      assert Inventory.basket_role(basket.id, stranger.id) == nil
      refute Inventory.can_access_basket?(stranger.id, basket.id)
    end

    test "people/1 lists the owner first and never exposes an email", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      people = basket.id |> Inventory.get_shopping_basket!() |> Sharing.people()

      assert [%{id: owner_id, role: :owner}, %{id: friend_id, role: :member}] = people
      assert owner_id == owner.id
      assert friend_id == friend.id
      refute Enum.any?(people, &(&1.name in [owner.email, friend.email]))
    end

    test "a member can leave; a member cannot remove someone else", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      other = confirmed_user()
      share!(owner, basket, other)

      assert {:error, :forbidden} = Sharing.remove_member(friend, basket.id, other.id)
      assert :ok = Sharing.remove_member(friend, basket.id, friend.id)
      assert Inventory.basket_role(basket.id, friend.id) == nil
      assert Inventory.basket_role(basket.id, other.id) == :member
    end

    test "the owner can remove a member", %{owner: owner, basket: basket, friend: friend} do
      assert :ok = Sharing.remove_member(owner, basket.id, friend.id)
      assert Inventory.get_accessible_basket(friend.id, basket.id) == nil
      assert {:error, :not_found} = Sharing.remove_member(owner, basket.id, friend.id)
    end

    test "blocking removes the pair from each other's lists", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      :ok = Moderation.block_user(owner, friend.id)
      assert Inventory.basket_role(basket.id, friend.id) == nil
    end

    test "deleting the owner's account hands the list to a member", %{
      owner: owner,
      basket: basket,
      friend: friend
    } do
      solo = basket_for(owner, "Private")
      {:ok, _} = Inventory.add_item(basket.id, %{name: "Milk", quantity: 1.0})

      {:ok, _} = Accounts.delete_user(owner)

      survivor = Inventory.get_accessible_basket(friend.id, basket.id)
      assert survivor.user_id == friend.id
      assert survivor.members == []
      assert [%{name: "Milk"}] = survivor.basket_items
      assert Repo.get(Mehungry.Inventory.ShoppingBasket, solo.id) == nil
    end
  end

  describe "shared writes" do
    setup %{owner: owner, basket: basket, friend: friend} do
      share!(owner, basket, friend)

      {:ok, item} =
        Inventory.add_item(basket.id, %{name: "Eggs", quantity: 6.0, added_by_id: owner.id})

      %{item: item}
    end

    test "attribution is recorded", %{item: item, owner: owner, friend: friend} do
      assert item.added_by_id == owner.id

      assert {:ok, ticked} = Inventory.set_acquired(item, true, friend.id)
      assert ticked.in_storage
      assert ticked.acquired_by_id == friend.id

      assert {:ok, unticked} = Inventory.set_acquired(ticked, false, friend.id)
      assert unticked.acquired_by_id == nil
    end

    test "two people ticking the same line both leave it ticked", %{
      item: item,
      owner: owner,
      friend: friend
    } do
      # Both act on the same stale, un-ticked copy.
      assert {:ok, _} = Inventory.set_acquired(item, true, owner.id)
      assert {:ok, _} = Inventory.set_acquired(item, true, friend.id)

      assert Inventory.get_basket_item!(item.id).in_storage
    end

    test "acting on a line someone else deleted does not raise", %{item: item, friend: friend} do
      {:ok, _} = Inventory.delete_basket_item(item)

      assert {:ok, _} = Inventory.delete_basket_item(item)
      assert {:error, :not_found} = Inventory.set_acquired(item, true, friend.id)
      assert {:error, %Ecto.Changeset{}} = Inventory.update_basket_item(item, %{quantity: 2.0})
    end

    test "changes are broadcast to other subscribers, not echoed to the caller", %{
      basket: basket,
      item: item,
      friend: friend
    } do
      basket_id = basket.id
      :ok = Inventory.subscribe(basket_id)
      # Another session (its own process) makes the changes.
      elsewhere = fn fun -> fun |> Task.async() |> Task.await() end

      elsewhere.(fn -> {:ok, _} = Inventory.set_acquired(item, true, friend.id) end)
      assert_receive {:basket_changed, ^basket_id}

      elsewhere.(fn ->
        {:ok, _} = Inventory.add_item(basket_id, %{name: "Bread", quantity: 1.0})
      end)

      assert_receive {:basket_changed, ^basket_id}

      # A change this process makes itself is not echoed back to it.
      {:ok, _} = Inventory.add_item(basket_id, %{name: "Jam", quantity: 1.0})
      refute_receive {:basket_changed, ^basket_id}, 50

      elsewhere.(fn ->
        {:ok, _} = Inventory.delete_shopping_basket(Inventory.get_shopping_basket!(basket_id))
      end)

      assert_receive {:basket_deleted, ^basket_id}
    end
  end
end
