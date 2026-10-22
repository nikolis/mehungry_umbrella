defmodule Mehungry.Notifications.ExpoPushClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.Notifications.ExpoPush` (wired via the
  `:expo_push_client` config key in `config/test.exs`) so tests never hit Expo.

  By default it returns one `%{"status" => "ok"}` ticket per message. A test can
  override with a `push` fn via app config:

      Application.put_env(:mehungry, :expo_push_stub,
        push: fn messages ->
          send(test_pid, {:expo_push, messages})
          {:ok, Enum.map(messages, fn _ -> %{"status" => "ok"} end)}
        end
      )
      on_exit(fn -> Application.delete_env(:mehungry, :expo_push_stub) end)
  """
  @behaviour Mehungry.Notifications.ExpoPushClient

  @impl true
  def push(messages) do
    case Application.get_env(:mehungry, :expo_push_stub)[:push] do
      fun when is_function(fun, 1) -> fun.(messages)
      _ -> {:ok, Enum.map(messages, fn _ -> %{"status" => "ok"} end)}
    end
  end
end
