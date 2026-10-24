defmodule Mehungry.NotificationsDevicesTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Notifications
  import Mehungry.AccountsFixtures, only: [user_fixture: 0]

  describe "register_device/3" do
    test "registers a token for a user" do
      user = user_fixture()
      assert {:ok, device} = Notifications.register_device(user.id, "ExpoTok[abc]", "ios")
      assert device.user_id == user.id
      assert device.platform == "ios"
      assert Notifications.tokens_for_user(user.id) == ["ExpoTok[abc]"]
    end

    test "re-registering the same token upserts (no duplicate)" do
      user = user_fixture()
      {:ok, _} = Notifications.register_device(user.id, "ExpoTok[abc]", "ios")
      {:ok, _} = Notifications.register_device(user.id, "ExpoTok[abc]", "android")

      assert Notifications.tokens_for_user(user.id) == ["ExpoTok[abc]"]
    end

    test "a token re-registered by another user moves to that user" do
      a = user_fixture()
      b = user_fixture()
      {:ok, _} = Notifications.register_device(a.id, "ExpoTok[abc]", "ios")
      {:ok, _} = Notifications.register_device(b.id, "ExpoTok[abc]", "ios")

      assert Notifications.tokens_for_user(a.id) == []
      assert Notifications.tokens_for_user(b.id) == ["ExpoTok[abc]"]
    end

    test "rejects an invalid platform" do
      user = user_fixture()
      assert {:error, changeset} = Notifications.register_device(user.id, "ExpoTok[x]", "symbian")
      assert %{platform: _} = errors_on(changeset)
    end
  end

  describe "delete" do
    test "delete_device/2 is scoped to the owner" do
      a = user_fixture()
      b = user_fixture()
      {:ok, _} = Notifications.register_device(a.id, "ExpoTok[a]", "ios")

      :ok = Notifications.delete_device(b.id, "ExpoTok[a]")
      assert Notifications.tokens_for_user(a.id) == ["ExpoTok[a]"]

      :ok = Notifications.delete_device(a.id, "ExpoTok[a]")
      assert Notifications.tokens_for_user(a.id) == []
    end

    test "delete_device_token/1 removes regardless of owner" do
      a = user_fixture()
      {:ok, _} = Notifications.register_device(a.id, "ExpoTok[a]", "ios")

      :ok = Notifications.delete_device_token("ExpoTok[a]")
      assert Notifications.tokens_for_user(a.id) == []
    end
  end
end
