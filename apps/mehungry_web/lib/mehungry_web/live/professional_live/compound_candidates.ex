defmodule MehungryWeb.ProfessionalLive.CompoundCandidates do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.CandidateDerivationRuns

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, CandidateDerivationRuns.topic())
    end

    run = CandidateDerivationRuns.latest_run()

    socket =
      socket
      |> assign(:page_title, "Compound Candidates")
      |> assign(:page, 1)
      |> assign(:rel_page, 1)
      |> assign(:rel_count, Food.count_relationships())
      |> assign(:run, run)
      |> assign(:progress, progress_for(run))
      |> assign(:compounds, Food.list_compounds())
      |> assign(:measurable, Food.list_curated_ingredients())
      |> assign(:mcand_count, Food.count_pending_measurement_candidates())
      |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0))
      |> stream(:relationships, Food.list_relationships_page(limit: @per_page, offset: 0))
      |> stream(
        :measurement_candidates,
        Food.list_measurement_candidates(limit: @per_page, offset: 0)
      )
      |> stream(:measurements, Food.list_recent_measurements(limit: @per_page))

    {:ok, socket}
  end

  # ── Triggers / review ──────────────────────────────────────────────────

  @impl true
  def handle_event("derive", _params, socket) do
    {:ok, run} = Food.enqueue_candidate_derivation()

    {:noreply,
     socket
     |> assign(:run, run)
     |> put_flash(:info, "Derivation started — progress updates live below")}
  end

  @impl true
  def handle_event("promote", %{"id" => id}, socket) do
    {:ok, _} = Food.promote_candidate(String.to_integer(id))
    {:noreply, stream_delete_by_dom_id(socket, :candidates, "candidates-#{id}")}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_candidate(String.to_integer(id))
    {:noreply, stream_delete_by_dom_id(socket, :candidates, "candidates-#{id}")}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: offset))}
  end

  # ── Curated facts (promoted relationships) ─────────────────────────────────

  @impl true
  def handle_event("undo", %{"id" => id}, socket) do
    {:ok, _} = Food.unpromote_relationship(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:rel_count, max(socket.assigns.rel_count - 1, 0))
     |> stream_delete_by_dom_id(:relationships, "relationships-#{id}")}
  end

  @impl true
  def handle_event("purge", _params, socket) do
    {rels, _cands} = Food.purge_blocklisted()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Purged #{rels} non-dietary fact#{if rels == 1, do: "", else: "s"} (blocklist)"
     )
     |> assign(:rel_page, 1)
     |> assign(:rel_count, Food.count_relationships())
     |> stream(:relationships, Food.list_relationships_page(limit: @per_page, offset: 0),
       reset: true
     )}
  end

  @impl true
  def handle_event("load-more-rel", _params, socket) do
    page = socket.assigns.rel_page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:rel_page, page)
     |> stream(:relationships, Food.list_relationships_page(limit: @per_page, offset: offset))}
  end

  # ── Extracted measurement candidates (review) ──────────────────────────────

  @impl true
  def handle_event("accept_measurement", %{"id" => id}, socket) do
    case Food.accept_measurement_candidate(String.to_integer(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Measurement accepted and recorded.")
         |> assign(:mcand_count, max(socket.assigns.mcand_count - 1, 0))
         |> stream_delete_by_dom_id(:measurement_candidates, "measurement_candidates-#{id}")
         |> stream(:measurements, Food.list_recent_measurements(limit: @per_page), reset: true)}

      {:error, :no_curated_ingredient} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "That species has no curated ingredient to attach the measurement to."
         )}
    end
  end

  @impl true
  def handle_event("reject_measurement", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_measurement_candidate(String.to_integer(id))

    {:noreply,
     socket
     |> put_flash(:info, "Measurement candidate rejected.")
     |> assign(:mcand_count, max(socket.assigns.mcand_count - 1, 0))
     |> stream_delete_by_dom_id(:measurement_candidates, "measurement_candidates-#{id}")}
  end

  # ── Measurements (the strong "contains" evidence) ──────────────────────────

  @impl true
  def handle_event("add_measurement", %{"measurement" => params}, socket) do
    with %{"ingredient_id" => iid, "compound_id" => cid} when iid != "" and cid != "" <- params,
         ingredient_id <- String.to_integer(iid),
         compound_id <- String.to_integer(cid),
         {:ok, _measurement} <-
           Food.record_measurement(measurement_attrs(params, ingredient_id, compound_id)) do
      # Re-score the species candidate so the new measurement is reflected at once.
      case Food.species_id_for_ingredient(ingredient_id) do
        nil -> :ok
        species_id -> Food.derive_candidate(species_id, compound_id)
      end

      {:noreply,
       socket
       |> put_flash(:info, "Measurement recorded — re-scored the candidate.")
       |> assign(:page, 1)
       |> assign(:rel_page, 1)
       |> assign(:rel_count, Food.count_relationships())
       |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0),
         reset: true
       )
       |> stream(:relationships, Food.list_relationships_page(limit: @per_page, offset: 0),
         reset: true
       )}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, "Could not record measurement: #{errors(cs)}")}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Pick an ingredient and compound, and enter a value + unit.")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    run = CandidateDerivationRuns.latest_run()

    {:noreply,
     socket
     |> assign(:page, 1)
     |> assign(:rel_page, 1)
     |> assign(:rel_count, Food.count_relationships())
     |> assign(:run, run)
     |> assign(:progress, progress_for(run))
     |> assign(:mcand_count, Food.count_pending_measurement_candidates())
     |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0),
       reset: true
     )
     |> stream(:relationships, Food.list_relationships_page(limit: @per_page, offset: 0),
       reset: true
     )
     |> stream(
       :measurement_candidates,
       Food.list_measurement_candidates(limit: @per_page, offset: 0),
       reset: true
     )
     |> stream(:measurements, Food.list_recent_measurements(limit: @per_page), reset: true)}
  end

  # Live run broadcasts drive ONLY the progress bar; the review stream is left
  # untouched mid-run so rows don't shift under a reviewer (they Refresh manually).
  @impl true
  def handle_info({:candidate_derivation_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:run, run)
     |> assign(:progress, %{processed: run.processed || 0, total: run.total || 0})}
  end

  # ── View helpers ───────────────────────────────────────────────────────

  defp non_dietary_names, do: Food.non_dietary_compound_names()

  @extraction_methods ~w(manual automated pdf)
  defp extraction_methods, do: @extraction_methods

  defp field_class,
    do:
      "rounded border border-ink-panel2 bg-ink-panel2 text-parchment text-sm px-3 py-1.5 placeholder:text-parchment-dim"

  defp measurement_attrs(params, ingredient_id, compound_id) do
    %{
      ingredient_id: ingredient_id,
      compound_id: compound_id,
      value: parse_float(params["value"]),
      unit: blank(params["unit"]),
      preparation_method: blank(params["preparation_method"]),
      analytical_method: blank(params["analytical_method"]),
      sample_size: parse_int(params["sample_size"]),
      extraction_method: blank(params["extraction_method"]) || "manual",
      study_id: study_id_for(params["pmid"])
    }
  end

  # Link the measurement to a discovered study if the PMID is one we've crawled.
  defp study_id_for(pmid) do
    with pmid when is_binary(pmid) and pmid != "" <- pmid,
         {n, _} <- Integer.parse(pmid),
         %{id: id} <- Mehungry.Literature.get_study_by_pmid(n) do
      id
    else
      _ -> nil
    end
  end

  defp parse_float(s) when is_binary(s) and s != "" do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(_), do: nil

  defp parse_int(s) when is_binary(s) and s != "" do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp blank(s) when s in [nil, ""], do: nil
  defp blank(s), do: s

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp progress_for(nil), do: Food.candidate_derivation_progress()
  defp progress_for(run), do: %{processed: run.processed || 0, total: run.total || 0}

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{processed: processed, total: total}), do: round(processed / total * 100)

  defp running?(%{status: status}) when status in ["pending", "processing"], do: true
  defp running?(_), do: false

  defp run_label(nil), do: "Idle"
  defp run_label(%{status: "pending"}), do: "Queued…"
  defp run_label(%{status: "processing"}), do: "Deriving…"

  defp run_label(%{status: "completed"} = r),
    do: "Completed · #{r.promoted_count || 0} auto-promoted"

  defp run_label(%{status: "failed"}), do: "Failed"
  defp run_label(_), do: "Idle"

  defp run_class(%{status: "pending"}), do: "text-parchment-dim"
  defp run_class(%{status: "processing"}), do: "text-basil"
  defp run_class(%{status: "completed"}), do: "text-basil"
  defp run_class(%{status: "failed"}), do: "text-red-400"
  defp run_class(_), do: "text-parchment-dim"

  defp run_error(%{status: "failed", error: error}) when is_binary(error), do: error
  defp run_error(_), do: nil

  defp score_label(nil), do: "—"
  defp score_label(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 2)
  defp score_label(score), do: to_string(score)

  defp level_class("strong"), do: "text-basil"
  defp level_class("moderate"), do: "text-parchment"
  defp level_class("limited"), do: "text-parchment-dim"
  defp level_class(_), do: "text-parchment-dim"
end
