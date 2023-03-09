defmodule MehungryWeb.Searchable do
  def transfers_to_search do
    quote do
      def handle_event("validate", %{"recipe_search_item" => search_item} = thing, socket) do
        IO.inspect(thing, label: "Thing")
        IO.inspect("General handle event23sadffadsfasdfadsafds")
        {:noreply, socket}
      end

      def handle_event(
            "search",
            %{"recipe_search_item" => %{"query_string" => query_string}},
            socket
          ) do
        IO.inspect("General handle event23sadffadsfasdfadsafds")
        IO.inspect(query_string, label: "Query String")
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/browse")}
      end
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
