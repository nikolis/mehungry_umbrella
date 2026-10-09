defmodule MehungryWeb.FeedChannel do
  @moduledoc """
  Live feed (spec §13 `feed:lobby`). Public — anyone may join. The server pushes
  `"recipe_created"` and `"recipe_liked"` events, broadcast from the API layer
  when recipes are published or liked.
  """
  use MehungryWeb, :channel

  @impl true
  def join("feed:lobby", _payload, socket), do: {:ok, socket}
  def join(_topic, _payload, _socket), do: {:error, %{reason: "unknown topic"}}
end
