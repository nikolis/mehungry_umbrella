defmodule MehungryWeb.ProfessionalLive.Studies do
  @moduledoc """
  Review page for pipeline stage 1 (Paper discovery). Browses the discovered
  `ScientificStudy` records, searchable by title/PMID and paginated, with a
  crawl-ledger summary. Expanding a row shows the ingredients the paper was
  linked to and the entity mentions extracted from it (stage 2).

  Pure web wiring over `Mehungry.Literature` review reads. See
  `docs/scientific_pipeline.md`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Literature

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Discovered Studies")
      |> assign(:search, "")
      |> assign(:page, 1)
      |> assign(:open_id, nil)
      |> assign(:detail, nil)
      |> assign(:total_all, Literature.count_studies())
      |> assign(:ledger, Literature.crawl_ledger_summary())
      |> load_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(search: q, page: 1, open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, socket |> assign(search: "", page: 1, open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("prev", _params, socket) do
    page = max(socket.assigns.page - 1, 1)
    {:noreply, socket |> assign(page: page, open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("next", _params, socket) do
    page = min(socket.assigns.page + 1, max_page(socket.assigns.total))
    {:noreply, socket |> assign(page: page, open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> assign(:total_all, Literature.count_studies())
     |> assign(:ledger, Literature.crawl_ledger_summary())
     |> assign(open_id: nil, detail: nil)
     |> load_page()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)

    if socket.assigns.open_id == id do
      {:noreply, assign(socket, open_id: nil, detail: nil)}
    else
      detail = %{
        ingredients: Literature.list_ingredients_for_study(id),
        mentions: Literature.list_entity_mentions_for_study(id)
      }

      {:noreply, assign(socket, open_id: id, detail: detail)}
    end
  end

  defp load_page(socket) do
    %{page: page, search: search} = socket.assigns
    offset = (page - 1) * @per_page
    studies = Literature.list_studies_page(limit: @per_page, offset: offset, search: search)
    ids = Enum.map(studies, & &1.id)

    socket
    |> assign(:studies, studies)
    |> assign(:total, Literature.count_studies_matching(search))
    |> assign(:ing_counts, Literature.study_ingredient_counts(ids))
    |> assign(:mention_counts, Literature.study_mention_counts(ids))
  end

  # ── View helpers ───────────────────────────────────────────────────────────

  defp max_page(total), do: max(ceil(total / @per_page), 1)
  defp pubmed_url(pmid), do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp meta_line(study) do
    [study.journal, study.publication_date]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
  end

  defp mention_class("chemical"), do: "text-basil"
  defp mention_class("disease"), do: "text-red-400"
  defp mention_class("species"), do: "text-parchment"
  defp mention_class(_), do: "text-parchment-dim"
end
