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

      def mount(params, session, socket) do
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
