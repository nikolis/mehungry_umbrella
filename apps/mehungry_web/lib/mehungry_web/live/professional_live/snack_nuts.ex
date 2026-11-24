defmodule MehungryWeb.ProfessionalLive.SnackNuts do
  @moduledoc """
  Admin curation of the snack foods the AI meal-plan assistant may offer
  (`Mehungry.Food.SnackIngredients`), one tab per kind (`?kind=`):

    * **Dried nuts** (`"dried_nut"`) — offered in any month.
    * **Fresh fruit** (`"fresh_fruit"`) — offered only in the months the fruit's
      species is locally on the market in the person's country (seasonality).

  Left: the current selection (remove). Right: a search over the global
  ingredient catalog, by default restricted to the kind's categories (add).
  """

  use MehungryWeb, :live_view

  alias Mehungry.Food

  @page_size 50

  @kind_tabs [
    {"dried_nut", "Dried nuts", "nuts", "Nut & seed categories only", "almond"},
    {"fresh_fruit", "Fresh fruit", "fruit", "Fruit categories only", "apple"}
  ]

  # ── mount ────────────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Snack foods")
      |> assign(:kind_tabs, @kind_tabs)
      |> assign(:kind, "dried_nut")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    kind =
      if params["kind"] in Food.SnackIngredients.kinds(), do: params["kind"], else: "dried_nut"

    socket =
      socket
      |> assign(:kind, kind)
      |> assign(:tab, List.keyfind(@kind_tabs, kind, 0))
      |> assign(:search, "")
      |> assign(:category_only, true)
      |> load_selected()
      |> load_results(reset: true)

    {:noreply, socket}
  end

  # ── events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search", params, socket) do
    socket =
      socket
      |> assign(:search, Map.get(params, "search", ""))
      |> assign(:category_only, Map.get(params, "category_only") == "true")
      |> load_results(reset: true)

    {:noreply, socket}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load_results(socket, reset: false)}
  end

  def handle_event("add", %{"id" => id}, socket) do
    {:ok, _} =
      Food.add_snack_ingredient(String.to_integer(id), socket.assigns.kind, user_id(socket))

    {:noreply, load_selected(socket)}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    Food.remove_snack_ingredient(String.to_integer(id), socket.assigns.kind)
    {:noreply, load_selected(socket)}
  end

  # ── loading ──────────────────────────────────────────────────────────────────

  defp load_selected(socket) do
    selected = Food.list_snack_ingredients(socket.assigns.kind)

    socket
    |> assign(:selected, selected)
    |> assign(:selected_ids, MapSet.new(selected, & &1.ingredient_id))
  end

  defp load_results(socket, reset: reset?) do
    offset = if reset?, do: 0, else: length(socket.assigns.results)

    page =
      Food.search_snack_candidates(socket.assigns.search,
        kind: socket.assigns.kind,
        category_only: socket.assigns.category_only,
        limit: @page_size,
        offset: offset
      )

    results = if reset?, do: page, else: socket.assigns.results ++ page

    socket
    |> assign(:results, results)
    |> assign(:more?, length(page) == @page_size)
  end

  defp user_id(socket), do: socket.assigns.current_user && socket.assigns.current_user.id
end
