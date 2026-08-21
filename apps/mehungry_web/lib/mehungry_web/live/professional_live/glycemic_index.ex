defmodule MehungryWeb.ProfessionalLive.GlycemicIndex do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Glycemic Index")
      |> assign(:page, 1)
      |> assign(:promoted_page, 1)
      |> assign(:pending_count, Food.count_pending_glycemic_candidates())
      |> assign(:promoted_count, Food.count_promoted_glycemic_candidates())
      |> assign(:species, Food.list_foundemental_species())
      |> stream(:candidates, Food.list_pending_glycemic_candidates(limit: @per_page, offset: 0))
      |> stream(:promoted, Food.list_promoted_glycemic_candidates(limit: @per_page, offset: 0))

    {:ok, socket}
  end

  # ── Review ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("promote", %{"candidate_id" => id} = params, socket) do
    result =
      case params["species_id"] do
        sid when is_binary(sid) and sid != "" ->
          Food.promote_glycemic_candidate(String.to_integer(id), String.to_integer(sid))

        _ ->
          Food.promote_glycemic_candidate(String.to_integer(id))
      end

    case result do
      {:ok, _candidate} ->
        {:noreply,
         socket
         |> assign(:pending_count, max(socket.assigns.pending_count - 1, 0))
         |> assign(:promoted_count, socket.assigns.promoted_count + 1)
         |> stream_delete_by_dom_id(:candidates, "candidates-#{id}")
         |> stream(:promoted, Food.list_promoted_glycemic_candidates(limit: @per_page, offset: 0),
           reset: true
         )}

      {:error, :no_ingredients} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "That species has no curated ingredients to attach the GI value to — assign one in the USDA Schema view first."
         )}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_glycemic_candidate(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:pending_count, max(socket.assigns.pending_count - 1, 0))
     |> stream_delete_by_dom_id(:candidates, "candidates-#{id}")}
  end

  @impl true
  def handle_event("undo", %{"id" => id}, socket) do
    {:ok, _} = Food.unpromote_glycemic_candidate(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:promoted_count, max(socket.assigns.promoted_count - 1, 0))
     |> stream_delete_by_dom_id(:promoted, "promoted-#{id}")}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(
       :candidates,
       Food.list_pending_glycemic_candidates(limit: @per_page, offset: offset)
     )}
  end

  @impl true
  def handle_event("load-more-promoted", _params, socket) do
    page = socket.assigns.promoted_page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:promoted_page, page)
     |> stream(
       :promoted,
       Food.list_promoted_glycemic_candidates(limit: @per_page, offset: offset)
     )}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> assign(:page, 1)
     |> assign(:promoted_page, 1)
     |> assign(:pending_count, Food.count_pending_glycemic_candidates())
     |> assign(:promoted_count, Food.count_promoted_glycemic_candidates())
     |> stream(:candidates, Food.list_pending_glycemic_candidates(limit: @per_page, offset: 0),
       reset: true
     )
     |> stream(:promoted, Food.list_promoted_glycemic_candidates(limit: @per_page, offset: 0),
       reset: true
     )}
  end

  # ── View helpers ────────────────────────────────────────────────────────

  defp species_label(%{name: name, variety: variety}) when is_binary(variety) and variety != "",
    do: "#{name} (#{variety})"

  defp species_label(%{name: name}), do: name

  defp field_class,
    do:
      "rounded border border-ink-panel2 bg-ink-panel2 text-parchment text-sm px-2 py-1 placeholder:text-parchment-dim"

  # ISO 26642:2010-consistent method is the quality signal that replaces the old
  # Table-1/Table-2 tier (path B grades from the primary paper, not the table).
  defp iso_badge(%{iso_method: true}), do: {"ISO 26642", "text-basil"}
  defp iso_badge(_), do: {"non-ISO", "text-parchment-dim"}

  # Provenance is the primary study; show its PMID/DOI + a link.
  defp study_ref(%{study: %{pmid: pmid}}) when is_integer(pmid), do: "PMID #{pmid}"
  defp study_ref(%{study: %{doi: doi}}) when is_binary(doi) and doi != "", do: "doi:#{doi}"
  defp study_ref(_), do: "—"

  defp study_url(%{study: %{doi: doi}}) when is_binary(doi) and doi != "",
    do: "https://doi.org/#{doi}"

  defp study_url(%{study: %{pmid: pmid}}) when is_integer(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp study_url(_), do: nil

  defp study_title(%{study: %{title: title}}) when is_binary(title), do: title
  defp study_title(_), do: nil

  defp conf_label(nil), do: "—"
  defp conf_label(c) when is_float(c), do: :erlang.float_to_binary(c, decimals: 2)
  defp conf_label(c), do: to_string(c)

  defp gi_label(%{gi_value: gi, gi_sem: sem}) when is_float(sem),
    do: "GI #{trim_num(gi)} ± #{trim_num(sem)}"

  defp gi_label(%{gi_value: gi}), do: "GI #{trim_num(gi)}"

  defp trim_num(nil), do: "—"
  defp trim_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp trim_num(n), do: to_string(n)
end
