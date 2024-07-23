defmodule MehungryWeb.Searchable do
  @moduledoc false

  def transfers_to_search do
    quote do
      def handle_event("validate", %{"recipe_search_item" => search_item} = thing, socket) do
        {:noreply, socket}
      end

      def handle_event(
            "search",
            %{"recipe_search_item" => %{"query_string" => query_string}},
            socket
          ) do
            {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/browse/search/"<> query_string)}
      end
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
