defmodule MehungryWeb.ApiChannelsTest do
  use MehungryWeb.ChannelCase, async: true

  alias Mehungry.AccountsFixtures
  alias MehungryWeb.Api.Auth
  alias MehungryWeb.UserSocket

  defp connect_user(user) do
    {:ok, socket} = connect(UserSocket, %{"token" => Auth.mint(user)}, connect_info: %{})
    socket
  end

  describe "socket connect" do
    test "rejects an invalid token" do
      assert :error = connect(UserSocket, %{"token" => "garbage"}, connect_info: %{})
    end

    test "accepts a valid token and assigns user_id" do
      user = AccountsFixtures.user_fixture()
      {:ok, socket} = connect(UserSocket, %{"token" => Auth.mint(user)}, connect_info: %{})
      assert socket.assigns.user_id == user.id
    end

    test "allows an anonymous socket" do
      assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{})
      assert socket.assigns.user_id == nil
    end
  end

  describe "feed:lobby" do
    test "anyone can join and receives recipe_created broadcasts" do
      {:ok, socket} = connect(UserSocket, %{}, connect_info: %{})
      {:ok, _reply, _socket} = subscribe_and_join(socket, "feed:lobby", %{})

      MehungryWeb.Api.Broadcaster.recipe_created(%{id: 1, title: "X"})
      assert_push("recipe_created", %{recipe: %{id: 1}})
    end
  end

  describe "user:<id> authorization" do
    test "a user may join only its own topic" do
      user = AccountsFixtures.user_fixture()
      socket = connect_user(user)

      assert {:ok, _, _} = subscribe_and_join(socket, "user:#{user.id}", %{})
      assert {:error, %{reason: "unauthorized"}} = subscribe_and_join(socket, "user:#{user.id + 1}", %{})
    end

    test "receives notification broadcasts" do
      user = AccountsFixtures.user_fixture()
      actor = AccountsFixtures.user_fixture()
      socket = connect_user(user)
      {:ok, _, _} = subscribe_and_join(socket, "user:#{user.id}", %{})

      # Emission now runs through the core context seam (the configured web
      # dispatcher broadcasts to the channel).
      Mehungry.Notifications.emit(user.id, "follow",
        actor_id: actor.id,
        subject_type: "user",
        subject_id: actor.id
      )

      assert_push("notification", %{type: "follow", actor: %{id: actor_id}, subject: %{type: "user"}})
      assert actor_id == actor.id
    end
  end

  describe "meal_plan:<id> authorization" do
    test "a user may join only its own meal_plan topic" do
      user = AccountsFixtures.user_fixture()
      socket = connect_user(user)

      assert {:ok, _, _} = subscribe_and_join(socket, "meal_plan:#{user.id}", %{})
      assert {:error, _} = subscribe_and_join(socket, "meal_plan:#{user.id + 1}", %{})
    end
  end
end
