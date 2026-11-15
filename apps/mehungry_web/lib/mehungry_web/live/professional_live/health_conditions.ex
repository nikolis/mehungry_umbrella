defmodule MehungryWeb.ProfessionalLive.HealthConditions do
  @moduledoc """
  Admin page for curating the `Mehungry.Health` advice layer: create health
  conditions and manage their `CompoundRecommendation`s / `NutrientRecommendation`s.
  Recommendations are no longer hand-entered here — they arrive through the
  review-gated flows (promote a literature/phase candidate, or verify a derived
  suggestion) and are listed per condition with a Remove action. Compound
  recommendations reference **compounds** only; the implicated food species are
  resolved at read time (`Health.species_for_condition/2`).

  Also the biomed-fact-miner "Mine conditions" sweep (UI-managed URL + auth/JWT
  token) and a one-shot "Wipe extractor data" button that clears the dormant
  legacy `mehungry_extractor` tables (`PipelineReset.reset_extractor_data/0`).
  """
  use MehungryWeb, :live_view

  alias Mehungry.FactMining
  alias Mehungry.FactMining.ConditionFactMiningRuns, as: FactRuns
  alias Mehungry.Health
  alias Mehungry.Literature
  alias Mehungry.Health.ConditionSeeder
  alias Mehungry.MealBlueprints.DietPatterns
  alias Mehungry.Health.RecommendationCandidates
  alias Mehungry.Health.ConditionRecCandidates
  alias Mehungry.Science.PipelineReset

  @recommendations ~w(avoid limit caution monitor encourage)
  @severities ~w(low moderate high severe)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, FactRuns.topic())
    end

    socket =
      socket
      |> assign(:page_title, "Health Conditions")
      # Transient UI state (not derived from the DB, so not rebuilt in load/0).
      |> assign(:crawling, MapSet.new())
      |> assign(:miner_reachable, :unknown)
      # Per-condition "Mine facts": clicking a card opens a prompt modal; submitting
      # it mines that one condition (a one-row batch on the serialized :fact_mining
      # queue). `mining_conditions` = condition_ids whose mine is in flight (card
      # button state); `single_batch_ids` = the batch_ids those mines opened (so their
      # PubSub terminal events route back to the card). The modal holds the picked
      # condition + its (editable) prompt.
      |> assign(:mining_conditions, MapSet.new())
      |> assign(:single_batch_ids, MapSet.new())
      |> assign(:mine_modal_condition, nil)
      |> assign(:mine_query, "")

    socket =
      if connected?(socket),
        do: start_async(socket, :miner_reachable, fn -> FactMining.reachable?() end),
        else: socket

    {:ok,
     socket
     # Which conditions have their "Discovered papers" collapse open. Server-side
     # gated (not CSS-hidden) so the ~11k paper rows across all conditions are not
     # all rendered into the DOM up front — that made the page take forever to load.
     |> assign(:papers_open, MapSet.new())
     |> load()}
  end

  defp load(socket) do
    all_conditions = Health.list_conditions()

    # Papers discovered for each condition, rebuilt from the DB so they show
    # permanently underneath the condition — not just right after a crawl.
    condition_studies =
      Literature.studies_by_condition(Enum.map(all_conditions, & &1.id))

    # Conditions with associated papers float to the top, preserving the original
    # order within each group.
    conditions =
      Enum.sort_by(all_conditions, fn c ->
        if match?([_ | _], condition_studies[c.id]), do: 0, else: 1
      end)

    # Batched (one query each) so curating ~200 conditions doesn't fan out into a
    # per-condition N+1 on every load/0 (this runs after nearly every event).
    condition_ids = Enum.map(conditions, & &1.id)
    recs = Health.recommendations_by_conditions(condition_ids)
    nutrient_recs = Health.nutrient_recommendations_by_conditions(condition_ids)

    socket
    |> assign(:conditions, conditions)
    |> assign(:recs, recs)
    |> assign(:nutrient_recs, nutrient_recs)
    |> assign(:condition_studies, condition_studies)
    |> assign(:rec_candidates, RecommendationCandidates.list_pending_candidates())
    |> assign(:phase_candidates, ConditionRecCandidates.list_pending_candidates())
    |> assign_fact_miner_connection()
  end

  # The live fact-miner connection (UI-managed, env/config fallback) for the
  # "Mine conditions" settings form + the "currently using" line.
  defp assign_fact_miner_connection(socket) do
    {base_url, auth_token} = FactMining.connection()

    socket
    |> assign(:miner_base_url, base_url)
    |> assign(:miner_auth_token, auth_token)
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  # Bulk-load the bundled ~193-condition catalogue from
  # priv/repo/seeds/data/health_conditions.json. Idempotent (upsert on `name`),
  # so it is safe to click repeatedly — mirrors `mix run priv/repo/seeds.exs`,
  # which never runs against a prod release.
  @impl true
  def handle_event("seed_conditions", _params, socket) do
    {:ok, %{inserted: inserted, total: total}} = ConditionSeeder.seed()

    {:noreply,
     socket
     |> put_flash(:info, "Seeded condition registry: #{inserted} new, #{total} total.")
     |> load()}
  end

  @impl true
  def handle_event("seed_diet_patterns", _params, socket) do
    {:ok, tally} = DietPatterns.sync_for_user(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> put_flash(:info, DietPatterns.sync_summary(tally))
     |> load()}
  end

  @impl true
  def handle_event("clear_all_recommendations", _params, socket) do
    {:ok, %{candidates: candidates, recommendations: recommendations}} =
      Health.clear_all_recommendations_and_candidates()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Cleared the advice layer: #{candidates} candidate(s) and #{recommendations} recommendation(s) deleted. You can now create new ones."
     )
     |> load()}
  end

  # One-shot wipe of all dormant legacy `mehungry_extractor` data (study analyses,
  # extractor-sourced full texts, the saved analyzer connection, ingestion-run
  # history). The fact-miner data and all curated recommendations are kept.
  @impl true
  def handle_event("wipe_extractor_data", _params, socket) do
    counts = PipelineReset.reset_extractor_data()

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Wiped legacy extractor data: #{counts["study_analyses"]} analyses, " <>
         "#{counts["study_full_texts"]} extractor full texts, " <>
         "#{counts["extractor_settings"]} settings row(s), " <>
         "#{counts["research_ingestion_runs"]} ingestion run(s) deleted."
     )
     |> load()}
  end

  # Persist the fact-miner connection (URL + optional JWT/bearer token) that
  # "Mine all conditions" talks to. Takes effect immediately — no redeploy.
  @impl true
  def handle_event("save_fact_miner_settings", %{"settings" => params}, socket) do
    case FactMining.update_settings(params) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Fact-miner settings saved.")
          |> load()

        # Re-probe reachability against the new connection.
        {:noreply,
         if(connected?(socket),
           do:
             socket
             |> assign(:miner_reachable, :unknown)
             |> start_async(:miner_reachable, fn -> FactMining.reachable?() end),
           else: socket
         )}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not save fact-miner settings: #{errors(changeset)}")}
    end
  end

  @impl true
  def handle_event("save_condition", %{"condition" => params}, socket) do
    case Health.create_condition(normalize_synonyms(params)) do
      {:ok, _condition} ->
        {:noreply, socket |> put_flash(:info, "Condition added.") |> load()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add condition: #{errors(changeset)}")}
    end
  end

  @impl true
  def handle_event("delete_recommendation", %{"id" => id}, socket) do
    id |> String.to_integer() |> Health.get_recommendation!() |> Health.delete_recommendation()
    {:noreply, socket |> put_flash(:info, "Recommendation removed.") |> load()}
  end

  @impl true
  def handle_event("delete_nutrient_recommendation", %{"id" => id}, socket) do
    id
    |> String.to_integer()
    |> Health.get_nutrient_recommendation!()
    |> Health.delete_nutrient_recommendation()

    {:noreply, socket |> put_flash(:info, "Nutrient recommendation removed.") |> load()}
  end

  @impl true
  def handle_event("promote_recommendation", %{"candidate_id" => id} = params, socket) do
    attrs =
      params
      |> Map.take(["recommendation", "severity", "evidence_level"])
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    case RecommendationCandidates.promote_candidate(String.to_integer(id), attrs) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Recommendation promoted from literature.") |> load()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not promote: #{errors(changeset)}")}
    end
  end

  @impl true
  def handle_event("reject_recommendation", %{"id" => id}, socket) do
    {:ok, _} = RecommendationCandidates.reject_candidate(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Candidate rejected.") |> load()}
  end

  # ── Phase-aware (state-tagged) recommendation candidates ───────────────────

  @impl true
  def handle_event("promote_phase_candidate", %{"candidate_id" => id} = params, socket) do
    attrs =
      params
      |> Map.take(["recommendation", "severity", "evidence_level", "condition_state_id"])
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    case ConditionRecCandidates.promote_candidate(String.to_integer(id), attrs) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Phase-aware recommendation promoted.") |> load()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not promote: #{errors(changeset)}")}
    end
  end

  @impl true
  def handle_event("reject_phase_candidate", %{"id" => id}, socket) do
    {:ok, _} = ConditionRecCandidates.reject_candidate(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Phase candidate rejected.") |> load()}
  end

  @impl true
  def handle_event("delete_condition", %{"id" => id}, socket) do
    Health.delete_condition(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Condition removed.") |> load()}
  end

  # Re-assign a discovered paper to a better-fitting condition (typed into the
  # per-paper datalist). "Move + flag": it is linked to the target, removed from the
  # current condition, and flagged so a re-crawl of the current condition never
  # re-grabs it (see `Literature.reassign_study_to_condition/3`).
  @impl true
  def handle_event(
        "reassign_study",
        %{"study_id" => sid, "from_condition_id" => from, "target" => target_name},
        socket
      ) do
    target_name = String.trim(target_name || "")
    from_cid = String.to_integer(from)

    case Health.get_condition_by_name(target_name) do
      nil ->
        {:noreply,
         put_flash(socket, :error, "No condition named “#{target_name}” — pick one from the list.")}

      %{id: ^from_cid} ->
        {:noreply, put_flash(socket, :error, "That paper is already on this condition.")}

      target ->
        study_id = String.to_integer(sid)

        case Literature.reassign_study_to_condition(study_id, from_cid, target.id) do
          {:ok, %{already_present: already?}} ->
            msg =
              if already?,
                do: "“#{target.name}” already had this paper — flagged & removed from here.",
                else: "Paper re-assigned to “#{target.name}” and flagged here."

            {:noreply, socket |> put_flash(:info, msg) |> load()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not re-assign: #{inspect(reason)}")}
        end
    end
  end

  # ── Literature: per-condition PubMed crawl ──────────────────────────────────

  # Live crawl of PubMed for one condition (name × dietary/phase keywords), linking
  # discovered studies to the condition (study_conditions). Runs async so the UI
  # stays responsive; the ledgered crawl attempts make re-clicks cheap.
  @impl true
  def handle_event("search_condition_papers", %{"id" => id}, socket) do
    cid = String.to_integer(id)

    {:noreply,
     socket
     |> update(:crawling, &MapSet.put(&1, cid))
     |> start_async({:crawl, cid}, fn -> Literature.crawl_condition(cid) end)}
  end

  # Open the per-condition mine modal, pre-filling the prompt with the default
  # question (editable before mining).
  @impl true
  def handle_event("open_mine_modal", %{"id" => id}, socket) do
    socket =
      case Health.get_condition(String.to_integer(id)) do
        nil ->
          put_flash(socket, :error, "That condition no longer exists.")

        condition ->
          socket
          |> assign(:mine_modal_condition, condition)
          |> assign(:mine_query, FactMining.query_for_condition(condition))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_mine_modal", _params, socket) do
    {:noreply, assign(socket, :mine_modal_condition, nil)}
  end

  # Mine a single condition with the (possibly edited) prompt from the modal — a
  # one-row batch on the serialized :fact_mining queue. Its progress shows as the
  # card's own "Mining…" state + a result flash, routed by batch_id. The condition is
  # taken from the open modal's assign (the form carries only the edited query).
  @impl true
  def handle_event("mine_condition", %{"query" => query}, socket) do
    case socket.assigns.mine_modal_condition do
      %{id: cid} ->
        {:noreply,
         socket
         |> assign(:mine_modal_condition, nil)
         |> update(:mining_conditions, &MapSet.put(&1, cid))
         |> start_async({:mine_condition, cid}, fn -> FactRuns.mine_condition(cid, query) end)}

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("recheck_miner", _params, socket) do
    {:noreply,
     socket
     |> assign(:miner_reachable, :unknown)
     |> start_async(:miner_reachable, fn -> FactMining.reachable?() end)}
  end

  # Toggle a condition's "Discovered papers" collapse. Rendering the paper rows is
  # gated on this server-side (the data is already loaded) so a condition's papers —
  # each a heavy row with its own re-assign form — only enter the DOM when opened.
  @impl true
  def handle_event("toggle_condition_papers", %{"id" => id}, socket) do
    cid = String.to_integer(id)

    {:noreply,
     update(socket, :papers_open, fn open ->
       if MapSet.member?(open, cid), do: MapSet.delete(open, cid), else: MapSet.put(open, cid)
     end)}
  end

  @impl true
  # Live progress from a per-condition mine. A terminal transition for one of our
  # single-mine batches routes to the card (completion flash + button reset);
  # everything else (bulk-sweep rows from the dormant path, other sessions) is
  # ignored.
  def handle_info({:fact_mining_run, run}, socket) do
    if MapSet.member?(socket.assigns.single_batch_ids, run.batch_id) do
      {:noreply, handle_single_mine_run(socket, run)}
    else
      {:noreply, socket}
    end
  end

  # The slim "processing" edge carries no card state we don't already show
  # ("Mining…" is set when the mine is kicked off), so it's a no-op here.
  def handle_info({:fact_mining_processing, _batch_id, _condition_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_async(:miner_reachable, {:ok, result}, socket) do
    {:noreply, assign(socket, :miner_reachable, result)}
  end

  def handle_async(:miner_reachable, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :miner_reachable, {:error, :probe_crashed})}
  end

  # Per-condition mine kicked off: remember its batch so the terminal PubSub event
  # routes back to the card (the completion flash + button reset happen there).
  def handle_async({:mine_condition, _cid}, {:ok, {:ok, batch_id}}, socket) do
    {:noreply,
     socket
     |> update(:single_batch_ids, &MapSet.put(&1, batch_id))
     |> put_flash(:info, "Mining started — watch the condition's card.")}
  end

  def handle_async({:mine_condition, cid}, {:ok, {:error, {:already_running, _cid}}}, socket) do
    {:noreply,
     socket
     |> update(:mining_conditions, &MapSet.delete(&1, cid))
     |> put_flash(
       :error,
       "This condition already has a mine in the queue — wait for it to finish or cancel it first."
     )}
  end

  def handle_async({:mine_condition, cid}, {:ok, {:error, {:unreachable, reason}}}, socket) do
    {:noreply,
     socket
     |> update(:mining_conditions, &MapSet.delete(&1, cid))
     |> assign(:miner_reachable, {:error, reason})
     |> put_flash(:error, "Fact miner unreachable — #{inspect(reason)}")}
  end

  def handle_async({:mine_condition, cid}, {:ok, {:error, :not_found}}, socket) do
    {:noreply,
     socket
     |> update(:mining_conditions, &MapSet.delete(&1, cid))
     |> put_flash(:error, "That condition no longer exists.")}
  end

  def handle_async({:mine_condition, cid}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> update(:mining_conditions, &MapSet.delete(&1, cid))
     |> put_flash(:error, "Could not start mining — #{inspect(reason)}")}
  end

  @impl true
  def handle_async({:crawl, cid}, {:ok, result}, socket) do
    # Always reveal what's on record for the condition — even if this run errored
    # or found nothing new — so the admin sees previously-associated papers.
    socket =
      socket
      |> update(:crawling, &MapSet.delete(&1, cid))
      |> update(:condition_studies, &Map.put(&1, cid, Literature.list_studies_for_condition(cid)))

    socket =
      case result do
        {:ok, count} ->
          put_flash(socket, :info, "Search complete — #{count} new paper(s). Showing all on record.")

        {:error, reason} ->
          put_flash(socket, :error, "Search failed (showing papers on record): #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async({:crawl, cid}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> update(:crawling, &MapSet.delete(&1, cid))
     |> update(:condition_studies, &Map.put(&1, cid, Literature.list_studies_for_condition(cid)))
     |> put_flash(:error, "Search crashed (showing papers on record): #{inspect(reason)}")}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  # A tracking-row transition for a single-condition mine. On a terminal status
  # (completed/failed/cancelled) clear the card's "Mining…" state + flash the outcome;
  # a revert to `pending` (a 429 snooze / pending retry) leaves the card mining — it's
  # still queued. Mined facts feed the nutritionist research surface, not this page, so
  # no reload is needed.
  defp handle_single_mine_run(socket, %{status: status} = run)
       when status in ["completed", "failed", "cancelled"] do
    socket =
      socket
      |> update(:mining_conditions, &MapSet.delete(&1, run.condition_id))
      |> update(:single_batch_ids, &MapSet.delete(&1, run.batch_id))

    name = run.condition.name

    case status do
      "completed" ->
        put_flash(socket, :info, "Mined #{run.facts_total} fact(s) for “#{name}”.")

      "failed" ->
        put_flash(socket, :error, "Mining failed for “#{name}”: #{run.error}")

      "cancelled" ->
        put_flash(socket, :info, "Mining cancelled for “#{name}”.")
    end
  end

  defp handle_single_mine_run(socket, _run), do: socket

  # Split a comma-separated synonyms field into the array the schema expects.
  defp normalize_synonyms(%{"synonyms" => syn} = params) when is_binary(syn) do
    Map.put(
      params,
      "synonyms",
      syn |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    )
  end

  defp normalize_synonyms(params), do: params

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp recommendations, do: @recommendations
  defp severities, do: @severities

  defp select_class,
    do: "rounded border border-ink-panel2 bg-ink-panel2 text-parchment text-sm px-3 py-1.5"

  defp rec_class("avoid"), do: "text-red-400"
  defp rec_class("limit"), do: "text-paprika"
  defp rec_class("caution"), do: "text-parchment"
  defp rec_class(_), do: "text-basil"

  # The suggested direction, mapped to a valid CompoundRecommendation value for the
  # promote form's default (a "neutral"/nil suggestion has no valid value → caution).
  defp default_rec(s) when s in ~w(avoid limit caution monitor encourage), do: s
  defp default_rec(_), do: "caution"

  # The disease states for a phase candidate's condition (the promote form's state select).
  defp states_for_candidate(candidate), do: Health.list_states_for_condition(candidate.condition_id)

  # A human label for a phase candidate's target (resolved compound / nutrient / raw term).
  defp phase_target(%{compound: %{name: name}}) when is_binary(name), do: name
  defp phase_target(%{nutrient_name: name}) when is_binary(name) and name != "", do: name
  defp phase_target(%{raw_term: term}), do: term
end
