defmodule MehungryWeb.Searchable do
  @moduledoc false

  def transfers_to_search do
    quote do
      @type unsigned_params :: map
      @callback mount_search(
                  params :: unsigned_params() | :not_mounted_at_router,
                  session :: map,
                  socket :: Socket.t()
                ) ::
                  {:ok, Socket.t()} | {:ok, Socket.t(), keyword()}

      def get_address_agent(socket) do
        {first, second, third, forth} =
          Phoenix.LiveView.get_connect_info(socket, :peer_data).address

        address =
          Integer.to_string(first) <>
            "." <>
            Integer.to_string(second) <>
            "." <> Integer.to_string(third) <> "." <> Integer.to_string(forth)

        agent = Phoenix.LiveView.get_connect_info(socket, :user_agent)
        {address, agent}
      end

      @impl true
      def mount(params, session, socket) do
        {address, agent} = get_address_agent(socket)
        socket = assign(socket, :address, address)
        socket = assign(socket, :agent, agent)

        socket = assign(socket, :search_changeset, nil)

        socket = assign(socket, :search_changeset, nil)
        socket = assign(socket, :query_string, "")
        mount_search(params, session, socket)
      end

      def handle_event("validate", %{"recipe_search_item" => search_item} = thing, socket) do
        {:noreply, socket}
      end

      def handle_event(
            "search",
            %{"recipe_search_item" => %{"query_string" => query_string}},
            socket
          ) do
        case String.length(query_string) == 0 do
          true ->
            {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/browse")}

          false ->
            {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/search/" <> query_string)}
        end
      end
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
