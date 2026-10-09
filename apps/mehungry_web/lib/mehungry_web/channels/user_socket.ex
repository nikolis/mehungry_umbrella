defmodule MehungryWeb.UserSocket do
  use Phoenix.Socket

  alias MehungryWeb.Api.Auth

  ## Channels (mobile API — spec §13)
  channel("feed:*", MehungryWeb.FeedChannel)
  channel("recipe:*", MehungryWeb.RecipeChannel)
  channel("user:*", MehungryWeb.UserChannel)
  channel("meal_plan:*", MehungryWeb.MealPlanChannel)

  # The mobile client connects with `params: {token: "<bearer>"}` (the same
  # base64 session token used for REST). A valid token assigns `:user_id`;
  # otherwise the connection is refused. Anonymous connects are allowed only for
  # public topics, so we accept a tokenless socket with a nil user_id and let
  # each channel enforce its own authorization on join.
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Auth.verify(token) do
      {:ok, user} -> {:ok, assign(socket, :user_id, user.id)}
      :error -> :error
    end
  end

  def connect(_params, socket, _connect_info) do
    {:ok, assign(socket, :user_id, nil)}
  end

  @impl true
  def id(%{assigns: %{user_id: nil}}), do: nil
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
