defmodule MehungryWeb.ProfessionalLive.HealthConditions do
  @moduledoc """
  Admin page for curating the `Mehungry.Health` advice layer: create health
  conditions and attach `CompoundRecommendation`s (condition → compound → advice).
  Recommendations reference **compounds** only; the implicated food species are
  resolved at read time (`Health.species_for_condition/2`).
  """
  use MehungryWeb, :live_view

  alias Mehungry.Extractor
  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.Literature
  alias Mehungry.Health.ConditionSeeder
  alias Mehungry.MealBlueprints.DietPatterns
  alias Mehungry.Health.NutrientTargets
  alias Mehungry.Health.RecommendationCandidates
  alias Mehungry.Health.ConditionRecCandidates
  alias Mehungry.Health.ClaimRules

  @recommendations ~w(avoid limit caution monitor encourage)
  @severities ~w(low moderate high severe)
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(guideline manual literature ai)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Health Conditions")
     # Transient UI state (not derived from the DB, so not rebuilt in load/0).
     |> assign(:crawling, MapSet.new())
     |> assign(:analysis, nil)
     |> assign(:analyzing, false)
     # Per-condition "Claims & suggestions" detail block: which conditions are
     # expanded, their loaded data, and the active tab. Loaded lazily on expand
     # (the full condition list is large).
     |> assign(:expanded_conditions, MapSet.new())
     # cid => [%StudyAnalysis{}] (per-paper claims for Tab 1).
     |> assign(:condition_analyses, %{})
     # cid => [rule] (food-for-condition suggestions for Tab 2, via ClaimRules).
     |> assign(:condition_rules, %{})
     # cid => %{name: parent_name, rules: [rule]} — the parent condition's
     # suggestions, surfaced (labelled) under a subtype. Absent when no parent.
     |> assign(:condition_parent_rules, %{})
     # cid => "claims" | "suggestions" (active tab; defaults to "claims").
     |> assign(:condition_tab, %{})
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

    recs = Map.new(conditions, fn c -> {c.id, Health.recommendations_for_condition(c.id)} end)

    nutrient_recs =
      Map.new(conditions, fn c -> {c.id, Health.nutrient_recommendations_for_condition(c.id)} end)

    all_study_ids =
      condition_studies
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.id)

    # Studies (by id) that already have a stored extractor analysis, so the paper
    # list can mark them "analyzed" — rebuilt from the DB so it survives reloads.
    analyzed_study_ids = Literature.analyzed_study_ids(all_study_ids)

    # Studies whose stored analysis found the paper non-open-access: unusable for
    # now, so they're hidden from the selection list going forward. Rebuilt from
    # the DB so the hiding survives reloads.
    unusable_study_ids = Literature.unusable_study_ids(all_study_ids)

    socket
    |> assign(:conditions, conditions)
    |> assign(:recs, recs)
    |> assign(:nutrient_recs, nutrient_recs)
    |> assign(:condition_studies, condition_studies)
    |> assign(:analyzed_study_ids, analyzed_study_ids)
    |> assign(:unusable_study_ids, unusable_study_ids)
    |> assign(:nutrient_labels, Enum.sort(NutrientTargets.labels()))
    |> assign(:compounds, Food.list_compounds())
    |> assign(:rec_candidates, RecommendationCandidates.list_pending_candidates())
    |> assign(:phase_candidates, ConditionRecCandidates.list_pending_candidates())
    |> assign_extractor_connection()
  end

  # The live analyzer connection (UI-managed, env/config fallback) for the settings
  # form + the "currently using" line.
  defp assign_extractor_connection(socket) do
    {base_url, auth_token} = Extractor.connection()

    socket
    |> assign(:extractor_base_url, base_url)
    |> assign(:extractor_auth_token, auth_token)
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
    {:ok, created} = DietPatterns.create_missing_for_user(socket.assigns.current_user.id)

    flash =
      case created do
        0 -> "You already have all the starter diet-pattern blueprints (Mediterranean, Low-FODMAP)."
        n -> "Added #{n} starter diet-pattern blueprint#{if n == 1, do: "", else: "s"} (Mediterranean, Low-FODMAP)."
      end

    {:noreply,
     socket
     |> put_flash(:info, flash)
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

  # Persist the analyzer service connection (URL + optional bearer token) that
  # "Analyze selected" POSTs to. Takes effect immediately — no redeploy.
  @impl true
  def handle_event("save_extractor_settings", %{"settings" => params}, socket) do
    case Extractor.update_settings(params) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Analyzer service settings saved.") |> load()}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not save analyzer settings: #{errors(changeset)}")}
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
  def handle_event("save_recommendation", %{"recommendation" => params}, socket) do
    with %{"condition_id" => cid, "compound_id" => comp} when cid != "" and comp != "" <- params,
         # `add_recommendation/3` injects atom-keyed condition_id/compound_id, so the
         # rest must be atom-keyed too (Ecto rejects mixed string/atom keys).
         rec_attrs <-
           Map.take(params, ["recommendation", "severity", "evidence_level", "source", "notes"])
           |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
           |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
           |> maybe_put_source_reference(params),
         {:ok, _} <-
           Health.add_recommendation(String.to_integer(cid), String.to_integer(comp), rec_attrs) do
      {:noreply, socket |> put_flash(:info, "Recommendation added.") |> load()}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, put_flash(socket, :error, "Could not add recommendation: #{errors(cs)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Pick a condition and a compound first.")}
    end
  end

  @impl true
  def handle_event("delete_recommendation", %{"id" => id}, socket) do
    id |> String.to_integer() |> Health.get_recommendation!() |> Health.delete_recommendation()
    {:noreply, socket |> put_flash(:info, "Recommendation removed.") |> load()}
  end

  @impl true
  def handle_event("save_nutrient_recommendation", %{"recommendation" => params}, socket) do
    with %{"condition_id" => cid, "nutrient_name" => name} when cid != "" and name != "" <- params,
         rec_attrs <-
           Map.take(params, ["recommendation", "severity", "evidence_level", "source", "notes"])
           |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
           |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
           |> maybe_put_source_reference(params),
         {:ok, _} <-
           Health.add_nutrient_recommendation(String.to_integer(cid), name, rec_attrs) do
      {:noreply, socket |> put_flash(:info, "Nutrient recommendation added.") |> load()}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         put_flash(socket, :error, "Could not add nutrient recommendation: #{errors(cs)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Pick a condition and a nutrient first.")}
    end
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

  # ── Literature: per-condition PubMed crawl + extractor analysis ─────────────

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

  # Analyze the admin-selected PMIDs through the extractor's POST /analyze.
  @impl true
  def handle_event("analyze_condition", params, socket) do
    pmids = params |> Map.get("pmids", []) |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

    cond do
      pmids == [] ->
        {:noreply, put_flash(socket, :error, "Select at least one paper to analyze.")}

      length(pmids) > 200 ->
        {:noreply,
         put_flash(socket, :error, "The analyzer accepts at most 200 papers — select fewer.")}

      true ->
        {:noreply,
         socket
         |> assign(:analyzing, true)
         |> start_async(:analyze, fn -> extractor_client().analyze(pmids, []) end)}
    end
  end

  @impl true
  def handle_event("close_analysis", _params, socket) do
    {:noreply, assign(socket, :analysis, nil)}
  end

  # Toggle a condition's "Claims & suggestions" detail block. Initially folded;
  # on first expand the per-paper claims (Tab 1) and derived suggestions (Tab 2)
  # are loaded lazily and the active tab defaults to "claims".
  @impl true
  def handle_event("toggle_condition_detail", %{"id" => id}, socket) do
    cid = String.to_integer(id)

    if MapSet.member?(socket.assigns.expanded_conditions, cid) do
      {:noreply, update(socket, :expanded_conditions, &MapSet.delete(&1, cid))}
    else
      {:noreply,
       socket
       |> update(:expanded_conditions, &MapSet.put(&1, cid))
       |> update(:condition_tab, &Map.put_new(&1, cid, "claims"))
       |> load_condition_detail(cid)}
    end
  end

  # Switch the active tab ("claims" | "suggestions") for a condition.
  @impl true
  def handle_event("switch_condition_tab", %{"id" => id, "tab" => tab}, socket) do
    cid = String.to_integer(id)
    {:noreply, update(socket, :condition_tab, &Map.put(&1, cid, tab))}
  end

  # Re-evaluate a condition's suggestions (and claims) from the latest stored
  # analyses + curation — ClaimRules derives them live, so this just re-runs it.
  @impl true
  def handle_event("refresh_suggestions", %{"id" => id}, socket) do
    cid = String.to_integer(id)

    {:noreply,
     socket
     |> load_condition_detail(cid)
     |> put_flash(:info, "Suggestions re-evaluated.")}
  end

  # Set a derived suggestion's verification via its per-suggestion select. Picking a
  # direction promotes it into the curated advice layer (compound/nutrient
  # recommendation, source "literature") so it shows on the public condition page and
  # the `/conditions` listing; picking "— not verified —" recalls it. The rule is
  # re-derived server-side and matched by its stable `verify_key`, so the browser
  # never sends the (large) backing claim payload back.
  @impl true
  def handle_event(
        "set_suggestion_verification",
        %{"condition_id" => cid, "key" => key} = params,
        socket
      ) do
    cid = String.to_integer(cid)

    case Enum.find(ClaimRules.rules_for_condition(cid), &(&1.verify_key == key)) do
      nil ->
        {:noreply,
         put_flash(socket, :error, "That suggestion is no longer available — refresh and retry.")}

      rule ->
        direction = params["recommendation"]

        {result, message} =
          if direction in [nil, ""] do
            {ClaimRules.recall_suggestion(cid, rule),
             "Suggestion recalled — removed from the public condition page."}
          else
            attrs =
              %{recommendation: direction, severity: params["severity"]}
              |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
              |> Map.new()

            {ClaimRules.verify_suggestion(cid, rule, attrs),
             "Suggestion verified — it now appears on the public condition page."}
          end

        case result do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, message) |> load() |> load_condition_detail(cid)}

          {:error, :unmatched} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "This suggestion has no compound/nutrient match, so it can't be published."
             )}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, put_flash(socket, :error, "Could not update verification: #{errors(cs)}")}
        end
    end
  end

  # Set a claim's curation `position` (persisted into the StudyAnalysis jsonb),
  # then reload the condition's claims + suggestions so both tabs reflect it live
  # (only "food_related" claims feed the suggestions in Tab 2).
  @impl true
  def handle_event(
        "set_claim_position",
        %{"study" => sid, "claim" => claim_id, "position" => position, "condition" => cid},
        socket
      ) do
    study_id = String.to_integer(sid)
    cid = String.to_integer(cid)

    {:ok, _} = Literature.set_claim_position(study_id, claim_id, position)

    {:noreply, load_condition_detail(socket, cid)}
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

  @impl true
  def handle_async(:analyze, {:ok, {:ok, result}}, socket) do
    # Persist + reconcile the response against what's already stored (per paper),
    # then reload so the "analyzed" badges reflect the new rows.
    {:ok, counts} = Literature.store_analysis_response(result)

    {:noreply,
     socket
     |> assign(:analyzing, false)
     # Store the raw response; display an annotated copy that layers our derived
     # fields onto each claim (extractor data stays untouched).
     |> assign(:analysis, ClaimRules.annotate_analysis(result))
     |> load()
     |> put_flash(:info, analysis_saved_message(counts))}
  end

  @impl true
  def handle_async(:analyze, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(:analyzing, false) |> put_flash(:error, "Analysis failed: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:analyze, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(:analyzing, false) |> put_flash(:error, "Analysis crashed: #{inspect(reason)}")}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp extractor_client,
    do: Application.get_env(:mehungry, :extractor_client, Mehungry.Extractor.Client)

  # Load a condition's detail block: the stored per-paper analyses (Tab 1), the
  # derived food-for-condition suggestions (Tab 2), and — if the condition is a
  # subtype — its parent's suggestions (surfaced labelled under the child). All
  # read-only queries.
  defp load_condition_detail(socket, cid) do
    socket
    |> update(:condition_analyses, &Map.put(&1, cid, Literature.analyses_for_condition(cid)))
    |> update(:condition_rules, &Map.put(&1, cid, ClaimRules.rules_for_condition(cid)))
    |> load_parent_rules(cid)
  end

  defp load_parent_rules(socket, cid) do
    conditions = socket.assigns.conditions

    with %{parent_condition_id: pid} when not is_nil(pid) <- Enum.find(conditions, &(&1.id == cid)),
         %{name: parent_name} <- Enum.find(conditions, &(&1.id == pid)) do
      entry = %{name: parent_name, rules: ClaimRules.rules_for_condition(pid)}
      update(socket, :condition_parent_rules, &Map.put(&1, cid, entry))
    else
      _ -> update(socket, :condition_parent_rules, &Map.delete(&1, cid))
    end
  end

  # Suggestions (Tab 2) are only the rules backed by at least one "food_related"
  # claim — `paper_count` already counts food_related sources only.
  defp food_related_rules(rules), do: Enum.filter(rules || [], &(&1.paper_count > 0))

  # A rule's supporting claims that the admin marked "food_related".
  defp food_related_sources(rule), do: Enum.filter(rule.sources, &(&1.position == "food_related"))

  # Total claims across a condition's analyzed papers (the Claims-tab badge count).
  defp claims_total(nil), do: 0
  defp claims_total(analyses), do: Enum.reduce(analyses, 0, &(length(&1.claims || []) + &2))

  # Claims-tab papers: drop papers with no claims, then order by most recent
  # publication first, then largest sample size (papers missing a field sort last).
  defp ordered_analyses(analyses) do
    (analyses || [])
    |> Enum.reject(&((&1.claims || []) == []))
    |> Enum.sort_by(fn a -> {-(a.publication_year || 0), -(a.sample_size || 0)} end)
  end

  # The claim's "disease_state" qualifier value (e.g. "active flare"), or nil.
  defp disease_state(claim) do
    (claim["qualifiers"] || [])
    |> Enum.find_value(fn q ->
      if q["qualifier_type"] == "disease_state", do: q["value_text"]
    end)
  end

  # Tab-button styling; the active tab gets an underline + bright text.
  defp tab_class(active?) do
    base = "px-3 py-1.5 text-xs font-medium border-b-2 -mb-px"

    if active?,
      do: base <> " border-basil text-parchment",
      else: base <> " border-transparent text-parchment-dim hover:text-parchment"
  end

  # A single derived suggestion row (used for a condition's own suggestions and for
  # the inherited parent-condition suggestions). Pass `condition_id` to make the row
  # verifiable (promote into the public advice layer); omit it (inherited rows) for
  # a read-only row.
  attr :rule, :map, required: true
  attr :condition_id, :any, default: nil

  def suggestion_row(assigns) do
    ~H"""
    <div class="py-2 border-t border-ink-panel2 text-xs">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5">
        <span class="text-parchment-dim">suggests</span>
        <span class={"font-medium #{direction_class(@rule.direction)}"}>
          {@rule.direction}
        </span>
        <span class="text-parchment font-medium">{@rule.dietary_name}</span>
        <span class="text-parchment-dim">({kind_label(@rule.kind)})</span>
        <span
          :for={ds <- @rule.disease_states}
          class="text-[10px] px-2 py-0.5 rounded-full bg-paprika/20 text-paprika-soft"
          title="Disease state mentioned by the backing claims"
        >
          {ds}
        </span>
        <span :if={@rule.compound_id} class="text-parchment-dim">
          → compound ##{@rule.compound_id}
        </span>
        <span :if={@rule.nutrient_label} class="text-parchment-dim">
          → nutrient “{@rule.nutrient_label}”
        </span>
        <span :if={@rule[:species_id]} class="text-parchment-dim">
          → food species ##{@rule.species_id}
        </span>
        <span :if={@rule[:blueprint_id]} class="text-parchment-dim">
          → meal plan ##{@rule.blueprint_id}
        </span>
        <span class="text-parchment-dim">· {@rule.paper_count} paper(s)</span>
        <span class="text-parchment-dim">· score {@rule.score}</span>
        <%!-- Generic "already recommended" badge for advice we don't manage from the
             verification select: inherited (read-only) rows, or a target already
             curated from another source. A row we verified shows its own state in
             the select below instead. --%>
        <span
          :if={@rule.already_recommended? and (is_nil(@condition_id) or other_recommended?(@rule))}
          class="text-[10px] text-parchment-dim border border-ink-panel2 rounded px-1"
          title="A recommendation for this target already exists on this condition"
        >
          already recommended
        </span>
      </div>

      <div class="mt-1 space-y-1 pl-2 border-l-2 border-basil/30">
        <div :for={src <- food_related_sources(@rule)} class="text-parchment-dim">
          <span class="text-parchment">
            {src.claim["subject_name"] || src.claim["subject_text"]}
          </span>, {src.claim["predicate"]},
          <span class="text-parchment">
            {src.claim["object_name"] || src.claim["object_text"]}
          </span>
          <span class="text-parchment-dim">→</span>
          <span class={polarity_class(src.claim["polarity"])}>{src.claim["polarity"]}</span>
          <a
            :if={src.pmid}
            href={"https://pubmed.ncbi.nlm.nih.gov/#{src.pmid}/"}
            target="_blank"
            rel="noopener"
            class="text-basil hover:underline ml-1"
          >{src.pmid}</a>
          <%!-- The verbatim sentence the extractor pulled the claim from, so the
                reviewer can judge the suggestion against the paper's own words. --%>
          <p :if={first_quote(src.claim)} class="text-[11px] text-parchment-dim/80 italic mt-0.5">
            “{first_quote(src.claim)}”
          </p>
        </div>
      </div>

      <%!-- ── Human verification ──────────────────────────────────────────── --%>
      <%!-- Verifying promotes the suggestion into the curated advice layer
           (compound/nutrient recommendation, source "literature"), so it shows on
           the public condition page and the /conditions listing. The select doubles
           as the recall control: picking "— not verified —" removes it again. Shown
           only for a condition's own, registry-matched suggestions that aren't
           already curated from another source. --%>
      <form
        :if={@condition_id && verifiable?(@rule) && not other_recommended?(@rule)}
        phx-change="set_suggestion_verification"
        class="mt-1.5 flex flex-wrap items-center gap-2"
      >
        <input type="hidden" name="condition_id" value={@condition_id} />
        <input type="hidden" name="key" value={@rule.verify_key} />
        <span class="text-[11px] text-parchment-dim">Verification</span>
        <select name="recommendation" class={[select_class(), "text-[11px] py-0.5"]}>
          <option value="" selected={is_nil(@rule.verified_as)}>— not verified —</option>
          <option :for={r <- recommendations()} value={r} selected={@rule.verified_as == r}>
            {r}
          </option>
        </select>
        <select
          :if={is_nil(@rule.verified_as)}
          name="severity"
          class={[select_class(), "text-[11px] py-0.5"]}
        >
          <option value="">Severity…</option>
          <option :for={s <- severities()} value={s}>{s}</option>
        </select>
        <span
          :if={@rule.verified_as}
          class="text-[10px] text-basil border border-basil/40 rounded px-1"
          title="Published on the public condition page — pick “not verified” to recall"
        >
          ✓ verified
        </span>
      </form>

      <%!-- For an unmatched target the verification above still publishes, but only
           as a free-text note on the condition page (it maps to no real foods). --%>
      <p
        :if={@condition_id && @rule.kind == :unmatched && verifiable?(@rule)}
        class="mt-1 text-[11px] text-parchment-dim italic"
      >
        No registry match — publishes as a text-only note on the condition page (no food mapping).
      </p>

      <p
        :if={@condition_id && not verifiable?(@rule)}
        class="mt-1.5 text-[11px] text-parchment-dim"
      >
        No dietary term to publish — this suggestion can't be verified.
      </p>
    </div>
    """
  end

  # Every suggestion with a target can be published. A compound/nutrient promotes to
  # a food-mapping recommendation; a species/blueprint resolves to a concrete food
  # card / plan card on the condition page; an `:unmatched` one publishes as a
  # free-text note (no food mapping), so long as it carries a surface term to show.
  defp verifiable?(%{kind: :unmatched, dietary_name: name}), do: is_binary(name) and name != ""
  defp verifiable?(%{kind: kind}), do: kind in [:compound, :nutrient, :species, :blueprint]

  # True when the target already carries advice from a *different* source (hand
  # curated) and not a verification we own — we show a read-only badge and no
  # select, so this module never clobbers curated advice.
  defp other_recommended?(%{already_recommended?: recommended?, verified_as: verified}),
    do: recommended? and is_nil(verified)

  # Flash summary of a reconcile run (inserted/updated/unchanged/skipped paper rows).
  defp analysis_saved_message(%{inserted: i, updated: u, unchanged: n} = counts) do
    base = "Analysis saved: #{i} new, #{u} updated, #{n} unchanged"

    case Map.get(counts, :skipped, 0) do
      0 -> base <> "."
      s -> base <> " (#{s} skipped — no stored paper)."
    end
  end

  # First source quote for a claim, or nil. The extractor's `evidence` is a list
  # of `%{"quoted_text" => ...}` maps (may be absent/empty).
  defp first_quote(%{"evidence" => [%{"quoted_text" => q} | _]}) when is_binary(q), do: q
  defp first_quote(_), do: nil

  # Curation positions for the per-claim select ({value, label}); "" is the
  # unassigned option.
  defp position_options do
    [{"", "— unassigned —"} | Enum.map(Literature.claim_positions(), &{&1, position_label(&1)})]
  end

  defp position_label("food_related"), do: "Food related"
  defp position_label("general_science"), do: "General science"
  defp position_label("wrong"), do: "Wrong"
  defp position_label("ignore"), do: "Ignore"
  defp position_label(_), do: "— unassigned —"

  # How many of a condition's studies already have a stored extractor analysis.
  defp analyzed_count(studies, analyzed_study_ids),
    do: Enum.count(studies, &MapSet.member?(analyzed_study_ids, &1.id))

  # Total claims across every paper in the analyze response.
  defp claim_count(%{"paper_claims" => papers}) when is_list(papers) do
    Enum.reduce(papers, 0, fn pc, acc -> acc + length(pc["claims_list"] || []) end)
  end

  defp claim_count(_), do: 0

  # Badge tint for a claim's polarity (`positive` / `negative`).
  defp polarity_class("positive"), do: "text-basil"
  defp polarity_class("negative"), do: "text-paprika"
  defp polarity_class(_), do: "text-parchment-dim"

  # Badge tint for a paper's status (`included` / `outlier` / `error`).
  defp paper_status_class("included"), do: "text-basil"
  defp paper_status_class("error"), do: "text-paprika"
  defp paper_status_class(_), do: "text-parchment-dim"

  # Only full-text open-access papers are usable for extraction right now; an
  # `abstract` / `none` / unknown `source_type` is flagged unusable (and such
  # papers are then hidden from the selection list going forward).
  defp usable_source?("open_access"), do: true
  defp usable_source?(_), do: false

  # Split a comma-separated synonyms field into the array the schema expects.
  defp normalize_synonyms(%{"synonyms" => syn} = params) when is_binary(syn) do
    Map.put(
      params,
      "synonyms",
      syn |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    )
  end

  defp normalize_synonyms(params), do: params

  # Build the structured `source_reference` from the form's label/url fields. A
  # manual/guideline recommendation carries no PubMed study, so this is what satisfies
  # the CompoundRecommendation citation invariant; the schema guard rejects the save if
  # it's still empty for those sources.
  defp maybe_put_source_reference(attrs, params) do
    ref =
      %{"label" => params["reference_label"], "url" => params["reference_url"]}
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    if map_size(ref) > 0, do: Map.put(attrs, :source_reference, ref), else: attrs
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp recommendations, do: @recommendations
  defp severities, do: @severities
  defp evidence_levels, do: @evidence_levels
  defp sources, do: @sources

  defp select_class,
    do: "rounded border border-ink-panel2 bg-ink-panel2 text-parchment text-sm px-3 py-1.5"

  defp rec_class("avoid"), do: "text-red-400"
  defp rec_class("limit"), do: "text-paprika"
  defp rec_class("caution"), do: "text-parchment"
  defp rec_class(_), do: "text-basil"

  # Tint for a derived rule's suggested direction (encourage/avoid/review).
  defp direction_class("encourage"), do: "text-basil"
  defp direction_class("avoid"), do: "text-red-400"
  defp direction_class(_), do: "text-parchment-dim"

  # Short label for the dietary entity's registry match (drives what foods it maps to).
  defp kind_label(:compound), do: "compound"
  defp kind_label(:nutrient), do: "nutrient"
  defp kind_label(:species), do: "food species"
  defp kind_label(:blueprint), do: "meal plan"
  defp kind_label(_), do: "unmatched"

  # How the app resolved this observation's dietary endpoint to a foods-mapping
  # registry entry (or didn't).
  defp registry_match_label(%{kind: :compound, dietary_name: name}),
    do: "matched compound: #{name}"

  defp registry_match_label(%{kind: :nutrient, nutrient_label: label}),
    do: "matched nutrient: #{label}"

  defp registry_match_label(%{kind: :species, dietary_name: name}),
    do: "matched food species: #{name}"

  defp registry_match_label(%{kind: :blueprint, dietary_name: name}),
    do: "matched meal plan: #{name}"

  defp registry_match_label(%{dietary_name: name}),
    do: "no registry match (#{name})"

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
