defmodule MehungryWeb.ProfessionalLive.TaxonomyReview do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.TaxonomySeeder

  @per_page 25
  @slug "bio-nutritional"

  @impl true
  def mount(_params, _session, socket) do
    taxonomy = Food.get_taxonomy_by_slug(@slug) || List.first(Food.list_taxonomies())

    socket =
      socket
      |> assign(:taxonomy, taxonomy)
      |> assign(:page, 1)
      |> assign(:progress, progress_for(taxonomy))
      |> load_taxonomy_assigns()
      |> load_first_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    taxonomy = socket.assigns.taxonomy
    page = socket.assigns.page + 1
    offset = (page - 1) * @per_page

    mappings = pending(taxonomy, offset)

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(:mappings, mappings)}
  end

  @impl true
  def handle_event("confirm", %{"id" => id}, socket) do
    {:ok, _} = Food.review_mapping(String.to_integer(id), :confirm)

    {:noreply, stream_delete_by_dom_id(socket, :mappings, "mappings-#{id}")}
  end

  @impl true
  def handle_event("override", %{"mapping_id" => id, "node_id" => node_id}, socket)
      when node_id != "" do
    {:ok, _} = Food.review_mapping(String.to_integer(id), {:override, String.to_integer(node_id)})

    {:noreply,
     socket
     |> stream_delete_by_dom_id(:mappings, "mappings-#{id}")
     |> refresh_tree()}
  end

  def handle_event("override", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("seed", _params, socket) do
    TaxonomySeeder.seed()
    taxonomy = Food.get_taxonomy_by_slug(@slug) || List.first(Food.list_taxonomies())

    socket =
      socket
      |> assign(:taxonomy, taxonomy)
      |> assign(:page, 1)
      |> assign(:progress, progress_for(taxonomy))
      |> load_taxonomy_assigns()
      |> reset_first_page()
      |> put_flash(:info, "Taxonomy seeded")

    {:noreply, socket}
  end

  @impl true
  def handle_event("classify", _params, %{assigns: %{taxonomy: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Seed a taxonomy first")}
  end

  def handle_event("classify", _params, socket) do
    Food.enqueue_classification(socket.assigns.taxonomy.id)

    {:noreply, put_flash(socket, :info, "Classification started — refresh to watch progress")}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    taxonomy = socket.assigns.taxonomy

    {:noreply,
     socket
     |> assign(:page, 1)
     |> assign(:progress, progress_for(taxonomy))
     |> refresh_tree()
     |> reset_first_page()}
  end

  # ── Data loading ───────────────────────────────────────────────────────

  defp progress_for(nil), do: %{classified: 0, total: 0}
  defp progress_for(taxonomy), do: Food.classification_progress(taxonomy.id)

  defp reset_first_page(%{assigns: %{taxonomy: nil}} = socket) do
    stream(socket, :mappings, [], reset: true)
  end

  defp reset_first_page(%{assigns: %{taxonomy: taxonomy}} = socket) do
    stream(socket, :mappings, pending(taxonomy, 0), reset: true)
  end

  defp load_taxonomy_assigns(%{assigns: %{taxonomy: nil}} = socket) do
    socket
    |> assign(:tree, [])
    |> assign(:leaf_options, [])
    |> assign(:node_paths, %{})
  end

  defp load_taxonomy_assigns(%{assigns: %{taxonomy: taxonomy}} = socket) do
    leaves = Food.list_leaves_with_paths(taxonomy.id)

    socket
    |> assign(:tree, Food.build_tree(taxonomy.id))
    |> assign(:leaf_options, Enum.map(leaves, &{&1.path, &1.id}))
    |> assign(:node_paths, Map.new(leaves, &{&1.id, &1.path}))
  end

  defp load_first_page(%{assigns: %{taxonomy: nil}} = socket) do
    stream(socket, :mappings, [])
  end

  defp load_first_page(%{assigns: %{taxonomy: taxonomy}} = socket) do
    stream(socket, :mappings, pending(taxonomy, 0))
  end

  defp refresh_tree(%{assigns: %{taxonomy: nil}} = socket), do: socket

  defp refresh_tree(%{assigns: %{taxonomy: taxonomy}} = socket) do
    assign(socket, :tree, Food.build_tree(taxonomy.id))
  end

  defp pending(taxonomy, offset) do
    Food.list_pending_review(taxonomy.id, limit: @per_page, offset: offset)
  end

  # ── View helpers ───────────────────────────────────────────────────────

  defp node_path(node_paths, node) do
    Map.get(node_paths, node.id, node.name)
  end

  defp confidence_label(nil), do: "—"
  defp confidence_label(c) when is_float(c), do: :erlang.float_to_binary(c, decimals: 2)
  defp confidence_label(c), do: to_string(c)

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{classified: classified, total: total}), do: round(classified / total * 100)
end
