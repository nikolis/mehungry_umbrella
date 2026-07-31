defmodule MehungryWeb.ProfessionalLive.SchemaDiscovery do
  @moduledoc """
  Admin read-only view over `Mehungry.Food.SchemaDiscovery`: which structured
  dimensions the mined USDA ingredient names carry, how much of the corpus each
  covers, which are already captured by the parser, and which genuinely-new
  columns would be worth adding. Analysis is heavy (scans every ingredient) so it
  runs once on mount and on an explicit "Recompute" click — never on a timer.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food.SchemaDiscovery.{Coverage, Hybrid, PureEx}

  # Minimum cluster size the "> N" filter buttons can select. The filter drops
  # clusters of `size <= min` (e.g. min 1 hides singletons) — a display-only cut
  # over the already-computed groups, so it never re-embeds.
  @cluster_filters [0, 1, 2, 5, 10]

  # Cosine cutoffs the similarity knob can select. Moving it re-clusters the
  # cached embeddings (cheap); it does not re-embed.
  @threshold_options [0.75, 0.8, 0.85, 0.9, 0.95]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Schema Discovery")
     |> assign(:cluster_filters, @cluster_filters)
     |> assign(:min_cluster_size, 0)
     |> assign(:threshold_options, @threshold_options)
     |> assign(:cluster_threshold, Hybrid.default_threshold())
     |> load_report()}
  end

  @impl true
  def handle_event("recompute", _params, socket) do
    {:noreply, socket |> load_report() |> put_flash(:info, "Recomputed from current ingredients")}
  end

  @impl true
  def handle_event("filter_clusters", %{"min" => min}, socket) do
    {:noreply, assign(socket, :min_cluster_size, String.to_integer(min))}
  end

  @impl true
  def handle_event("set_threshold", %{"t" => t}, socket) do
    # Re-cluster the cached embeddings at the new cutoff — no re-embed.
    {:noreply, socket |> assign(:cluster_threshold, String.to_float(t)) |> recluster()}
  end

  defp load_report(socket) do
    analysis = PureEx.analyze()
    report = Coverage.recommend()
    {ingredients, embeddings} = embed_unmatched()

    socket
    |> assign(:total_ingredients, report.total_ingredients)
    |> assign(:parse_fill_rate, report.parse_fill_rate)
    |> assign(:projected_coverage, report.projected_coverage)
    |> assign(:dimensions, analysis.recommendations)
    |> assign(:migrations, report.migration_sql)
    |> assign(:summary, report.summary)
    |> assign(:sem_ingredients, ingredients)
    |> assign(:sem_embeddings, embeddings)
    |> recluster()
  end

  # Cluster the cached embeddings at the current threshold (cheap; no embedding).
  defp recluster(socket) do
    groups =
      Hybrid.group_embeddings(
        socket.assigns.sem_ingredients,
        socket.assigns.sem_embeddings,
        socket.assigns.cluster_threshold
      )

    assign(socket, :semantic_groups, groups)
  end

  # Embedding clustering is optional and off by default; only embed when enabled.
  defp embed_unmatched do
    if Application.get_env(:mehungry, :enable_embeddings, false) do
      Hybrid.unmatched_embeddings()
    else
      {[], []}
    end
  end

  # ── Render helpers ────────────────────────────────────────────────────────

  def pct(fraction), do: "#{round((fraction || 0.0) * 100)}%"

  def priority_class(priority) do
    cond do
      String.starts_with?(priority, "HIGH") ->
        "bg-paprika/20 text-paprika-soft border-paprika/30"

      String.starts_with?(priority, "MEDIUM") ->
        "bg-amber-500/20 text-amber-300 border-amber-500/30"

      String.starts_with?(priority, "LOW") ->
        "bg-basil/20 text-basil border-basil/30"

      true ->
        "bg-ink-panel2 text-parchment-dim border-ink-panel2"
    end
  end

  def top_values(dimension) do
    Enum.map_join(dimension.top_values, ", ", & &1.value)
  end

  @doc "Clusters larger than `min`, most-populous first."
  def visible_clusters(groups, min) do
    groups
    |> Enum.filter(&(&1.size > min))
    |> Enum.sort_by(& &1.size, :desc)
  end

  def cluster_filter_label(0), do: "All"
  def cluster_filter_label(min), do: "> #{min}"

  def cluster_filter_class(min, min), do: "bg-paprika text-ink border-paprika"

  def cluster_filter_class(_min, _selected),
    do: "border-ink-panel2 text-parchment hover:opacity-90"

  def threshold_label(t), do: :erlang.float_to_binary(t, decimals: 2)

  def threshold_class(t, t), do: "bg-paprika text-ink border-paprika"
  def threshold_class(_t, _selected), do: "border-ink-panel2 text-parchment hover:opacity-90"
end
