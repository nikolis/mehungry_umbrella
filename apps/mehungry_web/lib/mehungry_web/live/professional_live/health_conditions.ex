defmodule MehungryWeb.ProfessionalLive.HealthConditions do
  @moduledoc """
  Admin page for curating the `Mehungry.Health` advice layer: create health
  conditions and attach `CompoundRecommendation`s (condition → compound → advice).
  Recommendations reference **compounds** only; the implicated food species are
  resolved at read time (`Health.species_for_condition/2`).
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.Literature
  alias Mehungry.Health.ConditionSeeder
  alias Mehungry.Health.NutrientTargets
  alias Mehungry.Health.RecommendationCandidates
  alias Mehungry.Health.ConditionRecCandidates

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

    socket
    |> assign(:conditions, conditions)
    |> assign(:recs, recs)
    |> assign(:nutrient_recs, nutrient_recs)
    |> assign(:condition_studies, condition_studies)
    |> assign(:nutrient_labels, Enum.sort(NutrientTargets.labels()))
    |> assign(:compounds, Food.list_compounds())
    |> assign(:rec_candidates, RecommendationCandidates.list_pending_candidates())
    |> assign(:phase_candidates, ConditionRecCandidates.list_pending_candidates())
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
    {:noreply, socket |> assign(:analyzing, false) |> assign(:analysis, result)}
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

  # First source quote for a conclusion, or nil. The extractor's `evidence` is a
  # list of `%{"quoted_text" => ...}` maps (may be absent/empty).
  defp first_quote(%{"evidence" => [%{"quoted_text" => q} | _]}) when is_binary(q), do: q
  defp first_quote(_), do: nil

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
