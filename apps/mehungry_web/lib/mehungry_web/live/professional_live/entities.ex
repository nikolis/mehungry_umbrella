defmodule MehungryWeb.ProfessionalLive.Entities do
  @moduledoc """
  Review page for pipeline stage 2 (Entity annotation, PubTator3). Summarizes the
  extracted `StudyEntityMention` facts (chemicals/species/diseases) and the
  compounds they resolved into, and lets an admin browse the annotated studies and
  expand each to its mentions (chemicals link to the resolved compound).

  Pure web wiring over `Mehungry.Literature` review reads + `Mehungry.Food`
  compounds. See `docs/scientific_pipeline.md`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Literature

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_summary(socket) |> assign(page: 1, open_id: nil, detail: nil) |> load_page()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> load_summary() |> assign(open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("prev", _params, socket) do
    page = max(socket.assigns.page - 1, 1)
    {:noreply, socket |> assign(page: page, open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("next", _params, socket) do
    page = min(socket.assigns.page + 1, max_page(socket.assigns.total))
    {:noreply, socket |> assign(page: page, open_id: nil, detail: nil) |> load_page()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)

    if socket.assigns.open_id == id do
      {:noreply, assign(socket, open_id: nil, detail: nil)}
    else
      mentions = Literature.list_entity_mentions_for_study(id)
      {:noreply, assign(socket, open_id: id, detail: Enum.group_by(mentions, & &1.entity_type))}
    end
  end

  defp load_summary(socket) do
    socket
    |> assign(:page_title, "Extracted Entities")
    |> assign(:totals, Literature.mention_type_totals())
    |> assign(:annotated, Literature.count_annotated_studies())
    |> assign(:studies_total, Literature.annotation_progress().total)
    |> assign(:ledger, Literature.annotation_ledger_summary())
    |> assign(:compounds_by_id, Map.new(Food.list_compounds(), &{&1.id, &1.name}))
  end

  defp load_page(socket) do
    offset = (socket.assigns.page - 1) * @per_page
    studies = Literature.list_annotated_studies_page(limit: @per_page, offset: offset)
    ids = Enum.map(studies, & &1.id)

    socket
    |> assign(:studies, studies)
    |> assign(:total, socket.assigns.annotated)
    |> assign(:type_counts, Literature.study_mention_type_counts(ids))
  end

  # ── View helpers ───────────────────────────────────────────────────────────

  defp max_page(total), do: max(ceil(total / @per_page), 1)
  defp pubmed_url(pmid), do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp type_count(counts, study_id, type),
    do: counts |> Map.get(study_id, %{}) |> Map.get(type, 0)

  defp compounds_count(compounds_by_id), do: map_size(compounds_by_id)

  defp mention_class("chemical"), do: "text-basil"
  defp mention_class("disease"), do: "text-red-400"
  defp mention_class("species"), do: "text-parchment"
  defp mention_class(_), do: "text-parchment-dim"
end
