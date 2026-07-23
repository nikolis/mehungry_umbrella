defmodule MehungryWeb.ProfessionalLive.TaxonomyReview do
  use MehungryWeb, :live_view

  alias Mehungry.Food.Taxonomies
  alias MehungryWeb.AccordionComponent

  @taxonomy_slug "bio-nutritional"
  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    taxonomy = Taxonomies.get_taxonomy_by_slug(@taxonomy_slug)

    socket =
      socket
      |> assign(:page_title, "Ingredient Taxonomy Review")
      |> assign(:taxonomy, taxonomy)
      |> assign(:limit, @page_size)
      |> load_taxonomy_data()

    {:ok, socket}
  end

  @impl true
  def render(%{taxonomy: nil} = assigns) do
    ~H"""
    <div class="text-slate-300">
      <h1 class="text-xl font-bold text-white mb-2">Ingredient Taxonomy Review</h1>
      <p>
        No taxonomy found. Seed it first with <code class="text-amber-400">mix taxonomy.seed</code>.
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-xl font-bold text-white">Ingredient Taxonomy Review</h1>
          <p class="text-sm text-slate-400 mt-0.5">
            {@taxonomy.name} — confirm or override AI leaf assignments
          </p>
        </div>
        <div class="text-sm text-slate-400">
          <span class="text-amber-400 font-semibold">{@pending_count}</span> pending review
        </div>
      </div>

      <div class="mb-6 rounded-xl border border-slate-700/60 overflow-hidden">
        <div class="px-4 py-2 bg-slate-800/60 text-sm font-medium text-slate-300">
          Taxonomy tree (rolled-up ingredient counts)
        </div>
        <AccordionComponent.accordion items={@tree} accordion_id="taxonomy-tree" />
      </div>

      <div class="rounded-xl border border-slate-700/60 overflow-x-auto">
        <table class="w-full text-sm text-left">
          <thead class="bg-slate-800/60 text-slate-300">
            <tr>
              <th class="px-4 py-2 font-medium">Ingredient</th>
              <th class="px-4 py-2 font-medium">USDA category</th>
              <th class="px-4 py-2 font-medium">Assigned node</th>
              <th class="px-4 py-2 font-medium">Confidence</th>
              <th class="px-4 py-2 font-medium">Source</th>
              <th class="px-4 py-2 font-medium">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@pending == []}>
              <td colspan="6" class="px-4 py-6 text-center text-slate-400">
                Nothing pending review.
              </td>
            </tr>
            <tr
              :for={mapping <- @pending}
              id={"mapping-#{mapping.id}"}
              class="border-t border-slate-700/40 text-slate-200"
            >
              <td class="px-4 py-2">{mapping.ingredient.name}</td>
              <td class="px-4 py-2 text-slate-400">
                {mapping.ingredient.category && mapping.ingredient.category.name}
              </td>
              <td class="px-4 py-2">{node_path(mapping.taxonomy_node, @leaf_paths)}</td>
              <td class="px-4 py-2">{format_confidence(mapping.confidence)}</td>
              <td class="px-4 py-2 text-slate-400">{mapping.source}</td>
              <td class="px-4 py-2">
                <div class="flex items-center gap-2">
                  <button
                    phx-click="confirm"
                    phx-value-id={mapping.id}
                    class="px-2.5 py-1 rounded-lg bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-400 border border-emerald-500/30 text-xs font-medium transition-colors"
                  >
                    Confirm
                  </button>
                  <form phx-submit="override" class="flex items-center gap-1">
                    <input type="hidden" name="id" value={mapping.id} />
                    <select
                      name="node_id"
                      class="bg-slate-800 border border-slate-700/60 rounded-lg text-slate-200 text-xs px-2 py-1 focus:border-amber-500/50 focus:outline-none"
                    >
                      <option
                        :for={leaf <- @leaf_paths}
                        value={leaf.id}
                        selected={leaf.id == mapping.taxonomy_node_id}
                      >
                        {leaf.path}
                      </option>
                    </select>
                    <button
                      type="submit"
                      class="px-2.5 py-1 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 text-amber-400 border border-amber-500/30 text-xs font-medium transition-colors"
                    >
                      Override
                    </button>
                  </form>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@pending_count > length(@pending)} class="mt-4 text-center">
        <button
          phx-click="load-more"
          class="px-4 py-2 rounded-lg text-slate-300 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors"
        >
          Load more
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("confirm", %{"id" => id}, socket) do
    {:ok, _} = Taxonomies.review_mapping(String.to_integer(id), :confirm)

    {:noreply, load_taxonomy_data(socket)}
  end

  @impl true
  def handle_event("override", %{"id" => id, "node_id" => node_id}, socket) do
    {:ok, _} =
      Taxonomies.review_mapping(
        String.to_integer(id),
        {:override, String.to_integer(node_id)}
      )

    {:noreply, load_taxonomy_data(socket)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    socket = assign(socket, :limit, socket.assigns.limit + @page_size)

    {:noreply, load_taxonomy_data(socket)}
  end

  defp load_taxonomy_data(%{assigns: %{taxonomy: nil}} = socket), do: socket

  defp load_taxonomy_data(%{assigns: %{taxonomy: taxonomy}} = socket) do
    socket
    |> assign(:tree, Taxonomies.build_tree(taxonomy.id))
    |> assign(:pending, Taxonomies.list_pending_review(taxonomy.id, limit: socket.assigns.limit))
    |> assign(:pending_count, Taxonomies.count_pending_review(taxonomy.id))
    |> assign(:leaf_paths, Taxonomies.list_leaf_paths(taxonomy.id))
  end

  defp node_path(node, leaf_paths) do
    case Enum.find(leaf_paths, &(&1.id == node.id)) do
      nil -> node.name
      leaf -> leaf.path
    end
  end

  defp format_confidence(nil), do: "—"
  defp format_confidence(confidence), do: "#{round(confidence * 100)}%"
end
