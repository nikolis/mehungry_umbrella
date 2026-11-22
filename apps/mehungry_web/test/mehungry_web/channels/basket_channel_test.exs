defmodule MehungryWeb.BasketChannelTest do
  use MehungryWeb.ChannelCase, async: true

  alias Mehungry.Accounts
  alias Mehungry.AccountsFixtures
  alias Mehungry.Inventory
  alias MehungryWeb.Api.Auth
  alias MehungryWeb.UserSocket

  defp confirmed_user do
    user = AccountsFixtures.user_fixture()
    {:ok, %{user: user}} = Mehungry.Repo.transaction(Accounts.confirm_user_multi(user))
    user
  end

  defp connect_user(user) do
    {:ok, socket} = connect(UserSocket, %{"token" => Auth.mint(user)}, connect_info: %{})
    socket
  end

  setup do
    owner = confirmed_user()
    member = confirmed_user()
    {:ok, basket} = Inventory.create_shopping_basket(%{user_id: owner.id, title: "Shared"})
    {:ok, _, token} = Inventory.invite_to_basket(owner, basket.id)
    {:ok, _} = Inventory.accept_invitation_by_token(member, token)

    %{owner: owner, member: member, basket: basket}
  end

  test "owner and member can join; a stranger and an anonymous socket cannot", %{
    owner: owner,
    member: member,
    basket: basket
  } do
    topic = "basket:#{basket.id}"

    assert {:ok, _, _} = subscribe_and_join(connect_user(owner), topic, %{})
    assert {:ok, _, _} = subscribe_and_join(connect_user(member), topic, %{})

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(connect_user(confirmed_user()), topic, %{})

    {:ok, anonymous} = connect(UserSocket, %{}, connect_info: %{})
    assert {:error, %{reason: "unauthorized"}} = subscribe_and_join(anonymous, topic, %{})
  end

  test "a change to the list is pushed to subscribers", %{member: member, basket: basket} do
    basket_id = basket.id
    {:ok, _, _} = subscribe_and_join(connect_user(member), "basket:#{basket_id}", %{})

    {:ok, _} = Inventory.add_item(basket_id, %{name: "Olives", quantity: 1.0})
    assert_push("basket_changed", %{basket_id: ^basket_id})
  end

  test "a v2 subscriber is sent the item itself, not a poke", %{
    owner: owner,
    member: member,
    basket: basket
  } do
    basket_id = basket.id
    owner_id = owner.id
    {:ok, _, _} = subscribe_and_join(connect_user(member), "basket:#{basket_id}", %{"v" => 2})

    {:ok, item} =
      Inventory.add_item(basket_id, %{name: "Olives", quantity: 1.0, added_by_id: owner_id})

    item_id = item.id

    assert_push("item_upserted", %{
      basket_id: ^basket_id,
      actor_id: ^owner_id,
      item: %{id: ^item_id, name: "Olives", in_storage: false, aisle: _, added_by_id: ^owner_id}
    })

    {:ok, _} = Inventory.set_acquired(item, true, owner_id)

    assert_push("item_upserted", %{
      item: %{id: ^item_id, in_storage: true, acquired_by_id: ^owner_id}
    })

    {:ok, _} = Inventory.delete_basket_item(item)
    assert_push("item_deleted", %{basket_id: ^basket_id, id: ^item_id})
    refute_push("basket_changed", _)

    # A list-level change is still a poke.
    {:ok, _} = Inventory.update_shopping_basket(basket, %{title: "Renamed"})
    assert_push("basket_changed", %{basket_id: ^basket_id})
  end

  test "a removed member is closed out instead of updated", %{
    owner: owner,
    member: member,
    basket: basket
  } do
    basket_id = basket.id
    {:ok, _, _} = subscribe_and_join(connect_user(member), "basket:#{basket_id}", %{})

    :ok = Inventory.remove_basket_member(owner, basket_id, member.id)
    assert_push("basket_closed", %{basket_id: ^basket_id})
    refute_push("basket_changed", _)
  end
end
