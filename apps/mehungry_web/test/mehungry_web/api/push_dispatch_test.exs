defmodule MehungryWeb.Api.PushDispatchTest do
  # async: false — Presence is a global process (not sandboxed), so a tracked
  # socket must not race across tests.
  use MehungryWeb.ChannelCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.AccountsFixtures
  alias MehungryWeb.Api.Auth
  alias MehungryWeb.Api.PushDispatch
  alias MehungryWeb.UserSocket

  @worker Mehungry.ObanWorkers.PushNotificationWorker

  defp payload, do: %{"id" => 1, "type" => "follow", "actor" => %{"alias" => "B"}, "data" => %{}}

  defp join_user(user) do
    {:ok, socket} = connect(UserSocket, %{"token" => Auth.mint(user)}, connect_info: %{})
    {:ok, _, _} = subscribe_and_join(socket, "user:#{user.id}", %{})
    await_presence("user:#{user.id}")
  end

  defp await_presence(topic) do
    Enum.reduce_while(1..100, :timeout, fn _, _ ->
      if MehungryWeb.Presence.list(topic) != %{} do
        {:halt, :ok}
      else
        Process.sleep(10)
        {:cont, :timeout}
      end
    end)
  end

  test "enqueues a push when the recipient is NOT connected" do
    user = AccountsFixtures.user_fixture()

    assert :ok = PushDispatch.enqueue(user.id, payload())
    assert_enqueued(worker: @worker, args: %{"recipient_id" => user.id})
  end

  test "skips the push when the recipient IS connected (presence-gated)" do
    user = AccountsFixtures.user_fixture()
    assert :ok = join_user(user)

    assert :ok = PushDispatch.enqueue(user.id, payload())
    refute_enqueued(worker: @worker)
  end
end
