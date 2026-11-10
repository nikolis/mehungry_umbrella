defmodule MehungryWeb.ProfessionalLive.SpeciesEnrichmentReview do
  @moduledoc """
  Admin review queue for species enrichment facts (Wikidata CC0 + FAOSTAT CC BY) —
  see `docs/implementation/science/species_enrichment.md`. Facts fetched by
  `mix species.enrich` land `pending`; an admin promotes (surfaces on the species page)
  or rejects (sticky — a re-fetch won't resurrect it) here.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    pending = Food.list_pending_species_facts(limit: 500)

    socket
    |> assign(:groups, Enum.group_by(pending, & &1.species.name))
    |> assign(:pending_count, length(pending))
    |> assign(:promoted_count, Food.count_promoted_species_facts())
  end

  @impl true
  def handle_event("promote", %{"id" => id}, socket) do
    Food.promote_species_fact(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Promoted — it now shows on the species page.") |> load()}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    Food.reject_species_fact(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Rejected.") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-semibold mb-1">Species enrichment review</h1>
      <p class="text-sm text-gray-500 mb-6">
        {@pending_count} pending · {@promoted_count} promoted. Wikidata is CC0; FAOSTAT is
        CC BY 4.0 (credited on the page). Promote only facts whose matched entity is correct.
      </p>

      <div :if={@groups == %{}} class="text-gray-500 py-12 text-center">
        Nothing pending. Run <code>mix species.enrich</code> to fetch facts.
      </div>

      <div :for={{species_name, facts} <- Enum.sort_by(@groups, &elem(&1, 0))} class="mb-8">
        <h2 class="text-lg font-medium border-b pb-1 mb-3">{species_name}</h2>
        <ul class="space-y-2">
          <li
            :for={fact <- facts}
            class="flex items-start justify-between gap-4 rounded-lg border border-gray-200 p-3"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-xs font-semibold uppercase tracking-wide text-gray-400">
                  {fact_label(fact.fact_key)}{locale_tag(fact.locale)}
                </span>
                <a
                  :if={fact.enrichment_source && fact.enrichment_source.url}
                  href={fact.enrichment_source.url}
                  target="_blank"
                  rel="noopener"
                  class="text-xs text-blue-600 hover:underline"
                >
                  source ↗
                </a>
              </div>
              <p class="text-sm text-gray-800 mt-0.5 break-words">{fact_value(fact)}</p>
            </div>
            <div class="flex shrink-0 gap-2">
              <button
                phx-click="promote"
                phx-value-id={fact.id}
                class="rounded-md bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700"
              >
                Promote
              </button>
              <button
                phx-click="reject"
                phx-value-id={fact.id}
                class="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-50"
              >
                Reject
              </button>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp fact_label("origin_region"), do: "Origin"
  defp fact_label("description"), do: "Description"
  defp fact_label("wikipedia_url"), do: "Wikipedia"
  defp fact_label("top_producers"), do: "Top producers"
  defp fact_label(other), do: other

  defp locale_tag(locale) when locale in [nil, ""], do: ""
  defp locale_tag(locale), do: " · #{locale}"

  defp fact_value(%{fact_key: "top_producers", value_json: %{"producers" => producers}})
       when is_list(producers) do
    producers |> Enum.map(& &1["country"]) |> Enum.join(", ")
  end

  defp fact_value(%{value_text: text}), do: text
end
