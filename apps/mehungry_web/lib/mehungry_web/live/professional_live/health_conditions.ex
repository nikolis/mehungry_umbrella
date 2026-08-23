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
  alias Mehungry.Health.ConditionSeeder
  alias Mehungry.Health.RecommendationCandidates

  @recommendations ~w(avoid limit caution monitor encourage)
  @severities ~w(low moderate high severe)
  @evidence_levels ~w(strong moderate limited insufficient)
  @sources ~w(guideline manual literature ai)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Health Conditions") |> load()}
  end

  defp load(socket) do
    conditions = Health.list_conditions()
    recs = Map.new(conditions, fn c -> {c.id, Health.recommendations_for_condition(c.id)} end)

    socket
    |> assign(:conditions, conditions)
    |> assign(:recs, recs)
    |> assign(:compounds, Food.list_compounds())
    |> assign(:rec_candidates, RecommendationCandidates.list_pending_candidates())
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
           |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end),
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

  @impl true
  def handle_event("delete_condition", %{"id" => id}, socket) do
    Health.delete_condition(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Condition removed.") |> load()}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

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
end
