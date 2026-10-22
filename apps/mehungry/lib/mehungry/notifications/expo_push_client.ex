defmodule Mehungry.Notifications.ExpoPushClient do
  @moduledoc """
  Contract for the Expo push send, so tests can swap in a stub via the
  `:expo_push_client` app config key (same pattern as `:instagram_client`).

  `push/1` takes a list of Expo message maps
  (`%{to:, title:, body:, data:}`) and returns the Expo response `tickets`
  (one per message, in order) or a transport error.
  """

  @type message :: %{
          required(:to) => String.t(),
          required(:title) => String.t(),
          required(:body) => String.t(),
          optional(:data) => map()
        }

  @type ticket :: map()

  @callback push([message()]) :: {:ok, [ticket()]} | {:error, term()}
end
