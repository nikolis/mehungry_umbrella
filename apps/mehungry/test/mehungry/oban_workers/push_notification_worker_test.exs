defmodule Mehungry.ObanWorkers.PushNotificationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.AccountsFixtures, only: [user_fixture: 0]

  alias Mehungry.Notifications
  alias Mehungry.ObanWorkers.PushNotificationWorker

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :expo_push_stub) end)
    :ok
  end

  defp notification(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 1,
        "type" => "follow",
        "actor" => %{"id" => 2, "alias" => "Maria", "avatar_url" => nil},
        "subject" => %{"type" => "user", "id" => 2},
        "data" => %{},
        "read" => false,
        "inserted_at" => "2026-10-20T10:12:00Z"
      },
      overrides
    )
  end

  test "sends one Expo message per registered token" do
    user = user_fixture()
    {:ok, _} = Notifications.register_device(user.id, "ExpoTok[a]", "ios")
    {:ok, _} = Notifications.register_device(user.id, "ExpoTok[b]", "android")

    test_pid = self()

    Application.put_env(:mehungry, :expo_push_stub,
      push: fn messages ->
        send(test_pid, {:expo_push, messages})
        {:ok, Enum.map(messages, fn _ -> %{"status" => "ok"} end)}
      end
    )

    assert :ok = perform_job(PushNotificationWorker, %{"recipient_id" => user.id, "notification" => notification()})

    assert_received {:expo_push, messages}
    assert length(messages) == 2
    assert Enum.map(messages, & &1.to) |> Enum.sort() == ["ExpoTok[a]", "ExpoTok[b]"]
    assert Enum.all?(messages, &(&1.title == "New follower"))
    assert hd(messages).data["type"] == "follow"
  end

  test "comment copy uses the recipe title" do
    user = user_fixture()
    {:ok, _} = Notifications.register_device(user.id, "ExpoTok[a]", "ios")
    test_pid = self()

    Application.put_env(:mehungry, :expo_push_stub,
      push: fn messages ->
        send(test_pid, {:expo_push, messages})
        {:ok, Enum.map(messages, fn _ -> %{"status" => "ok"} end)}
      end
    )

    note = notification(%{"type" => "comment", "data" => %{"recipe_title" => "Fasolada"}})
    assert :ok = perform_job(PushNotificationWorker, %{"recipient_id" => user.id, "notification" => note})

    assert_received {:expo_push, [msg]}
    assert msg.title == "New comment"
    assert msg.body == "Maria commented on Fasolada"
  end

  test "prunes a token Expo reports as DeviceNotRegistered" do
    user = user_fixture()
    {:ok, _} = Notifications.register_device(user.id, "ExpoTok[dead]", "ios")

    Application.put_env(:mehungry, :expo_push_stub,
      push: fn _messages ->
        {:ok, [%{"status" => "error", "details" => %{"error" => "DeviceNotRegistered"}}]}
      end
    )

    assert :ok = perform_job(PushNotificationWorker, %{"recipient_id" => user.id, "notification" => notification()})
    assert Notifications.tokens_for_user(user.id) == []
  end

  test "no devices → no Expo call, still :ok" do
    user = user_fixture()
    test_pid = self()

    Application.put_env(:mehungry, :expo_push_stub,
      push: fn messages ->
        send(test_pid, {:expo_push, messages})
        {:ok, []}
      end
    )

    assert :ok = perform_job(PushNotificationWorker, %{"recipient_id" => user.id, "notification" => notification()})
    refute_received {:expo_push, _}
  end

  test "transport error returns {:error, _} for Oban retry" do
    user = user_fixture()
    {:ok, _} = Notifications.register_device(user.id, "ExpoTok[a]", "ios")

    Application.put_env(:mehungry, :expo_push_stub,
      push: fn _ -> {:error, {:transport_error, :timeout}} end
    )

    assert {:error, _} = perform_job(PushNotificationWorker, %{"recipient_id" => user.id, "notification" => notification()})
  end
end
