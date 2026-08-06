defmodule Mehungry.FriendsTest do
  use Mehungry.DataCase

  alias Mehungry.{Friends, Food, Users}
  alias Mehungry.Friends.{FriendRequest, Friendship}
  alias Mehungry.Food.IngredientSearch

  import Mehungry.{FoodFixtures, AccountsFixtures}

  defp user_ingredient_attrs(name) do
    category = category_fixture(%{})
    mu = measurement_unit_fixture()

    %{
      name: name,
      description: "custom",
      category_id: category.id,
      measurement_unit_id: mu.id
    }
  end

  describe "send_friend_request/3" do
    test "creates a pending request" do
      a = user_fixture()
      b = user_fixture()

      assert {:ok, %FriendRequest{} = req} = Friends.send_friend_request(a.id, b.id)
      assert req.status == "pending"
      assert req.requester_id == a.id
      assert req.recipient_id == b.id
    end

    test "rejects a self request" do
      a = user_fixture()
      assert {:error, :self} = Friends.send_friend_request(a.id, a.id)
    end

    test "rejects a duplicate pending request" do
      a = user_fixture()
      b = user_fixture()
      {:ok, _} = Friends.send_friend_request(a.id, b.id)
      assert {:error, :already_requested} = Friends.send_friend_request(a.id, b.id)
    end

    test "rejects when already friends" do
      a = user_fixture()
      b = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)
      {:ok, _} = Friends.accept_friend_request(req.id, b.id)
      assert {:error, :already_friends} = Friends.send_friend_request(a.id, b.id)
    end

    test "reuses a previously declined request" do
      a = user_fixture()
      b = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)
      {:ok, _} = Friends.decline_friend_request(req.id, b.id)

      assert {:ok, reused} = Friends.send_friend_request(a.id, b.id)
      assert reused.id == req.id
      assert reused.status == "pending"
    end
  end

  describe "accept_friend_request/2" do
    test "creates a normalized friendship and mutual follows" do
      a = user_fixture()
      b = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)

      assert {:ok, %Friendship{}} = Friends.accept_friend_request(req.id, b.id)
      assert Friends.friends?(a.id, b.id)
      assert Friends.friends?(b.id, a.id)

      a_follow_ids = a |> Users.list_user_follows() |> Enum.map(& &1.follow_id)
      b_follow_ids = b |> Users.list_user_follows() |> Enum.map(& &1.follow_id)
      assert b.id in a_follow_ids
      assert a.id in b_follow_ids
    end

    test "does not duplicate an existing follow" do
      a = user_fixture()
      b = user_fixture()
      # A already follows B before befriending.
      {:ok, _} = Users.save_user_follow(a.id, b.id)

      {:ok, req} = Friends.send_friend_request(a.id, b.id)
      {:ok, _} = Friends.accept_friend_request(req.id, b.id)

      a_follows_b = a |> Users.list_user_follows() |> Enum.filter(&(&1.follow_id == b.id))
      assert length(a_follows_b) == 1
    end

    test "rejects acceptance by the wrong user" do
      a = user_fixture()
      b = user_fixture()
      c = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)

      assert {:error, :unauthorized} = Friends.accept_friend_request(req.id, c.id)
    end
  end

  describe "cancel/decline" do
    test "requester can cancel a pending request" do
      a = user_fixture()
      b = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)

      assert {:ok, _} = Friends.cancel_friend_request(req.id, a.id)
      assert Friends.get_friend_request(req.id) == nil
    end

    test "non-requester cannot cancel" do
      a = user_fixture()
      b = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)

      assert {:error, :unauthorized} = Friends.cancel_friend_request(req.id, b.id)
    end
  end

  describe "list_friends / friend_ids / unfriend" do
    test "lists the other user and ends the friendship" do
      a = user_fixture()
      b = user_fixture()
      {:ok, req} = Friends.send_friend_request(a.id, b.id)
      {:ok, _} = Friends.accept_friend_request(req.id, b.id)

      assert Friends.friend_ids(a.id) == [b.id]
      assert [friend] = Friends.list_friends(a.id)
      assert friend.id == b.id

      assert {:ok, _} = Friends.unfriend(a.id, b.id)
      refute Friends.friends?(a.id, b.id)
      assert Friends.friend_ids(a.id) == []
    end
  end

  describe "blanket ingredient sharing" do
    test "friends see each other's private ingredients; unfriending revokes it" do
      a = user_fixture()
      b = user_fixture()

      {:ok, private} = Food.create_user_ingredient(a, user_ingredient_attrs("Snorfberry"))

      # Before friendship, B cannot see A's private ingredient.
      refute private.id in ("Snorfberry" |> IngredientSearch.search([], b.id) |> Enum.map(& &1.id))

      {:ok, req} = Friends.send_friend_request(a.id, b.id)
      {:ok, _} = Friends.accept_friend_request(req.id, b.id)

      # After friendship, it is visible in B's search and in B's friends list.
      assert private.id in ("Snorfberry" |> IngredientSearch.search([], b.id) |> Enum.map(& &1.id))
      assert private.id in (b |> Food.list_friends_ingredients() |> Enum.map(& &1.id))

      {:ok, _} = Friends.unfriend(a.id, b.id)
      refute private.id in ("Snorfberry" |> IngredientSearch.search([], b.id) |> Enum.map(& &1.id))
    end
  end
end
