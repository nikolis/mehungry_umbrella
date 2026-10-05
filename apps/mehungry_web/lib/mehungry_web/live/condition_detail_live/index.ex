defmodule MehungryWeb.ConditionDetailLive.Index do
  use MehungryWeb, :live_view

  import MehungryWeb.BlueprintComponents

  alias Mehungry.Accounts.UserContent
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Health
  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints
  alias Phoenix.LiveView.AsyncResult

  # Absolute origin for JSON-LD URLs (mirrors the canonical base in head.html.heex).
  @base_url "https://www.m3hungry.com"

  # Display order for the recommendation groups (labels are gettext'd at render).
  @recommendation_order ["avoid", "limit", "caution", "monitor", "encourage"]

  # ── Nutrition snapshot (mirrors SpeciesDetailLive.Index) ─────────────────────
  @top_nutrient_names [
    "Energy",
    "Protein",
    "Total lipid (fat)",
    "Carbohydrate, by difference",
    "Fiber, total dietary"
  ]

  @display_labels %{
    "Energy" => "Calories",
    "Protein" => "Protein",
    "Total lipid (fat)" => "Fat",
    "Carbohydrate, by difference" => "Carbs",
    "Fiber, total dietary" => "Fiber"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    language = socket.assigns[:current_language] || "en"

    case Health.get_condition(id, language) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/#{language}/conditions")}

      condition ->
        # Resolved synchronously (not via assign_async) so the disconnected HTTP
        # render — the only HTML a crawler ever sees — contains the real content
        # (compounds, foods, recipes) rather than loading skeletons.
        species = Health.species_for_condition(condition.id, nil, language)

        # Phase-aware layer (decoupled): a condition's disease states, the default
        # phase, its phase-specific advice, and the studies discovered about it.
        states = Health.list_states_for_condition(condition.id)
        default_state = Enum.find(states, & &1.is_default)

        state_recommendations =
          Health.state_recommendations_for_condition(
            condition.id,
            default_state && default_state.id,
            language
          )

        # Free-text dietary notes verified from the literature that resolved to no
        # registry entity (so they drive no food mapping). They live as general
        # (all-phase) `raw_food_term` rows; when the condition has disease states
        # they already surface under the phase selector's "General" tab, so we only
        # break them out into their own text-only block when there is no phase layer.
        general_notes =
          if states == [],
            do: Enum.filter(state_recommendations, &(&1.raw_food_term not in [nil, ""])),
            else: []

        condition_studies =
          condition.id |> Mehungry.Literature.list_studies_for_condition() |> Enum.take(30)

        page_title = seo_title(condition)
        page_description = seo_description(condition)

        recommendations = Health.recommendations_for_condition(condition.id, language)

        # Public blueprints keyed by normalized name, so any encouraged recommendation
        # title that matches a blueprint (e.g. "Mediterranean diet") — whether it comes
        # from the compound, phase, or free-text layer — linkifies to its preview modal.
        blueprint_links = MealBlueprints.public_blueprint_name_index()

        {:ok,
         socket
         |> assign(:condition, condition)
         |> assign(:language, language)
         |> assign_new(:current_user, fn -> nil end)
         |> assign(:current_user_recipes, saved_recipe_ids(socket))
         |> assign(:recommendations, AsyncResult.ok(recommendations))
         |> assign(:blueprint_links, blueprint_links)
         |> assign(:modal_blueprint, nil)
         |> assign(:modal_blueprint_plans, [])
         |> assign(:species, AsyncResult.ok(species))
         |> assign(:recommended_recipes, AsyncResult.ok(recommended_recipes(species)))
         |> assign(:states, states)
         |> assign(:selected_state, default_state)
         |> assign(:state_recommendations, state_recommendations)
         |> assign(:general_notes, general_notes)
         |> assign(:suggested_blueprints, Health.blueprints_for_condition(condition.id, language))
         |> assign(:condition_studies, condition_studies)
         |> assign(:page_title, page_title)
         |> assign(:page_description, page_description)
         |> assign(
           :structured_data,
           build_structured_data(condition, language, page_title, page_description)
         )}
    end
  end

  @doc """
  A compact "not medical advice" disclaimer badge, meant to sit in the upper-right
  corner of the advice frame. The short label carries the YMYL disclaimer; the
  longer "links the research…" note rides along as a hover tooltip.
  """
  def disclaimer_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-1 flex-shrink-0 rounded-full border border-paprika/40 bg-paprika/10 text-paprika-soft text-[10px] font-semibold uppercase tracking-wide px-2.5 py-1"
      title={
        gettext(
          "Each recommendation links the research it is based on so you can read the source and decide with your clinician."
        )
      }
    >
      <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      {gettext("Informational only — not medical advice")}
    </span>
    """
  end

  @doc """
  The general (phase-less) compound/nutrient dietary recommendations, rendered as
  grouped cards. Used both standalone (conditions with no disease phases) and nested
  under the phase panel's "General" tab (conditions that have phases) — advice
  without a state belongs to General.
  """
  attr :recommendations, :any, required: true
  attr :blueprint_links, :map, default: %{}

  def dietary_recommendations(assigns) do
    ~H"""
    <%= cond do %>
      <% @recommendations.loading -> %>
        <div class="space-y-3" aria-hidden="true">
          <div
            :for={_ <- 1..3}
            class="rounded-xl border border-ink-panel2 bg-ink-panel p-4 space-y-2"
          >
            <div class="m3-skeleton h-3.5 w-2/5 rounded bg-ink-panel2" />
            <div class="m3-skeleton h-3 w-3/5 rounded bg-ink-panel2" />
          </div>
        </div>
      <% @recommendations.failed -> %>
        <p class="text-parchment-dim text-sm">{gettext("Couldn't load recommendations.")}</p>
      <% @recommendations.ok? && length(@recommendations.result) == 0 -> %>
        <p class="text-parchment-dim text-sm">
          {gettext("No recommendations recorded for this condition yet.")}
        </p>
      <% true -> %>
        <div class="space-y-6">
          <%= for {rec, rows} <- grouped_recommendations(@recommendations.result) do %>
            <div>
              <h3 class="text-sm font-semibold text-paprika-soft uppercase tracking-wide mb-3">
                {recommendation_label(rec)}
              </h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <%= for row <- rows do %>
                  <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4">
                    <div class="flex items-start justify-between gap-2 mb-2">
                      <% bp_slug =
                        rec == "encourage" && blueprint_slug(@blueprint_links, row.compound.name) %>
                      <button
                        :if={bp_slug}
                        type="button"
                        phx-click="open_blueprint"
                        phx-value-slug={bp_slug}
                        class="text-left text-sm font-semibold text-basil hover:underline leading-snug cursor-pointer"
                      >
                        {row.compound.name}
                      </button>
                      <span
                        :if={!bp_slug}
                        class="text-sm font-semibold text-parchment leading-snug"
                      >
                        {row.compound.name}
                      </span>
                      <%= if row.severity do %>
                        <span class="text-xs px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim whitespace-nowrap">
                          {String.capitalize(row.severity)}
                        </span>
                      <% end %>
                    </div>
                    <div class="flex flex-wrap items-center gap-2 text-xs text-parchment-dim">
                      <%= if row.evidence_level do %>
                        <span class="px-2 py-0.5 rounded-full bg-ink-panel2">
                          {gettext("Evidence: %{level}",
                            level: String.capitalize(row.evidence_level)
                          )}
                        </span>
                      <% end %>
                      <span class="px-2 py-0.5 rounded-full bg-ink-panel2">
                        {String.capitalize(row.source)}
                      </span>
                    </div>
                    <%= if row.notes && row.notes != "" do %>
                      <p class="text-xs text-parchment-dim mt-2 leading-relaxed">{row.notes}</p>
                    <% end %>
                    <%!-- Sources: frozen PubMed provenance, else structured reference --%>
                    <%= cond do %>
                      <% row.studies != [] -> %>
                        <%!-- Collapsed to a small toggle while browsing; per-card
                              Alpine state + grid-rows 0fr→1fr transition (mirrors
                              the "Foods to Avoid or Limit" source lists). --%>
                        <div class="mt-3 pt-2 border-t border-ink-panel2" x-data="{ open: false }">
                          <button
                            type="button"
                            @click="open = !open"
                            class="cursor-pointer inline-flex items-center gap-1 text-[11px] text-parchment-dim hover:text-parchment transition-colors"
                          >
                            <svg
                              class="w-3 h-3 transition-transform duration-200"
                              x-bind:class="open && 'rotate-90'"
                              fill="none"
                              stroke="currentColor"
                              stroke-width="2"
                              viewBox="0 0 24 24"
                            >
                              <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                            </svg>
                            {gettext("Sources (%{count})", count: length(row.studies))}
                          </button>
                          <div
                            class="grid transition-all duration-200 ease-out"
                            style="grid-template-rows: 0fr"
                            x-bind:style="open ? 'grid-template-rows: 1fr' : 'grid-template-rows: 0fr'"
                          >
                            <div class="overflow-hidden">
                              <ul class="space-y-1 mt-2 pl-4">
                                <li :for={study <- row.studies} class="text-xs leading-snug">
                                  <a
                                    href={pubmed_url(study.pmid)}
                                    target="_blank"
                                    rel="noopener nofollow"
                                    class="text-basil hover:underline"
                                  >
                                    {study_label(study)}
                                  </a>
                                </li>
                              </ul>
                            </div>
                          </div>
                        </div>
                      <% is_map(row.source_reference) && reference_href(row.source_reference) -> %>
                        <div class="mt-3 pt-2 border-t border-ink-panel2">
                          <p class="text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-1">
                            {gettext("Source")}
                          </p>
                          <a
                            href={reference_href(row.source_reference)}
                            target="_blank"
                            rel="noopener nofollow"
                            class="text-xs text-basil hover:underline leading-snug"
                          >
                            {reference_label(row.source_reference)}
                          </a>
                        </div>
                      <% true -> %>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
    <% end %>
    """
  end

  @doc """
  A labelled row of blueprint target chips (Prefer / Avoid / Preferred foods) in
  the blueprint preview modal — mirrors the public preview page's `tag_row/1`.
  Renders nothing when there are no tags.
  """
  attr :label, :string, required: true
  attr :tags, :list, required: true
  attr :tone, :atom, required: true

  def blueprint_tag_row(%{tags: []} = assigns), do: ~H""

  def blueprint_tag_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5 mt-3">
      <span class="text-parchment-dim text-xs">{@label}:</span>
      <span
        :for={tag <- @tags}
        class={[
          "text-[11px] px-2 py-0.5 rounded-full",
          case @tone do
            :basil -> "bg-basil/15 text-basil"
            :paprika -> "bg-paprika/15 text-paprika-soft"
            _ -> "bg-ink-panel2 text-parchment-dim"
          end
        ]}
      >
        {tag}
      </span>
    </div>
    """
  end

  # Group phase-aware recommendations by direction, in the canonical display order —
  # mirrors grouped_recommendations/1 for the general layer.
  defp grouped_state_recommendations(recommendations) do
    recommendations
    |> Enum.group_by(& &1.recommendation)
    |> Enum.sort_by(fn {rec, _} -> Enum.find_index(@recommendation_order, &(&1 == rec)) || 99 end)
  end

  # A human label for a phase-aware recommendation's target
  # (compound / species / blueprint / nutrient / free-text pattern).
  defp state_rec_target(%{compound: %{name: name}}) when is_binary(name), do: name
  defp state_rec_target(%{species: %{name: name}}) when is_binary(name), do: name
  defp state_rec_target(%{blueprint: %{name: name}}) when is_binary(name), do: name
  defp state_rec_target(%{nutrient_name: name}) when is_binary(name) and name != "", do: name
  defp state_rec_target(%{raw_food_term: term}) when is_binary(term) and term != "", do: term
  defp state_rec_target(_), do: "—"

  @doc """
  Renders a phase/free-text recommendation target name. When `linkable` (the row
  is "encourage") and the name matches a public blueprint, it becomes a button
  that opens the blueprint preview modal; otherwise it is plain text.
  """
  attr :name, :string, required: true
  attr :linkable, :boolean, default: false
  attr :blueprint_links, :map, default: %{}

  def rec_target_name(assigns) do
    assigns =
      assign(
        assigns,
        :slug,
        assigns.linkable && blueprint_slug(assigns.blueprint_links, assigns.name)
      )

    ~H"""
    <button
      :if={@slug}
      type="button"
      phx-click="open_blueprint"
      phx-value-slug={@slug}
      class="text-left font-medium text-basil hover:underline cursor-pointer"
    >
      {@name}
    </button>
    <span :if={!@slug} class="text-parchment font-medium">{@name}</span>
    """
  end

  # ── SEO title/description ────────────────────────────────────────────────────
  # Lead with the words people actually search ("<condition> diet", "foods to
  # eat/avoid") rather than the scientific register the UI uses internally, while
  # staying localized. Computed synchronously in mount (not via assign_async) so
  # the disconnected render a crawler indexes carries the real title/description.
  # `head.html.heex` appends " | M3Hungry" for plain-string titles.
  defp seo_title(condition) do
    gettext("%{name} Diet: Foods to Eat & Avoid", name: condition.name)
  end

  defp seo_description(condition) do
    base =
      gettext(
        "%{name} diet guide: which foods to eat and which foods to avoid, with the nutrients and bioactive compounds behind each recommendation.",
        name: condition.name
      )

    case condition.synonyms do
      [_ | _] = syns ->
        base <>
          " " <> gettext("Also called %{names}.", names: Enum.join(Enum.take(syns, 3), ", "))

      _ ->
        base
    end
  end

  # `:show_food` opens the encouraged-food preview modal; loads a condensed slice
  # of the species page (identity is available immediately, the rest streams in).
  @impl true
  def handle_params(
        %{"species_id" => species_id},
        _uri,
        %{assigns: %{live_action: :show_food}} = socket
      ) do
    species =
      species_id
      |> Food.get_species_with_ingredients!()
      |> localize_species_name(socket.assigns[:language])

    {:noreply,
     socket
     |> assign(:modal_species, species)
     # The food-modal URL is a slice of the condition page; canonicalize to the
     # base page so crawlers don't treat it as duplicate content.
     |> assign(
       :canonical_path,
       ~p"/#{socket.assigns.language}/conditions/#{socket.assigns.condition.id}"
     )
     |> assign_async([:modal_nutrients, :modal_compounds, :modal_recipes], fn ->
       ingredients =
         species.foundemental_foods
         |> Enum.map(& &1.ingredient)
         |> Enum.reject(&is_nil/1)

       {:ok,
        %{
          modal_nutrients: top_nutrients_for(ingredients),
          modal_compounds: SpeciesCompounds.list_species_relationships(species.id),
          modal_recipes: sample_recipes_for(ingredients)
        }}
     end)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :modal_species, nil)}
  end

  # Save/unsave a sample recipe for later (guests are sent to log in first).
  @impl true
  def handle_event("save_user_recipe", %{"recipe_id" => recipe_id}, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:noreply, redirect(socket, to: ~p"/users/log_in")}

      user ->
        recipe_id = String.to_integer(recipe_id)

        if recipe_id in socket.assigns.current_user_recipes do
          UserContent.remove_user_saved_recipe(user.id, recipe_id)
        else
          UserContent.save_user_recipe(user.id, recipe_id)
        end

        {:noreply,
         assign(socket, :current_user_recipes, UserContent.list_user_saved_recipe_ids(user))}
    end
  end

  # Switch the phase whose phase-specific guidance is shown (decoupled state layer).
  def handle_event("select_state", %{"state" => slug}, socket) do
    condition = socket.assigns.condition
    language = socket.assigns.language

    selected =
      if slug in [nil, "", "general"],
        do: nil,
        else: Enum.find(socket.assigns.states, &(&1.slug == slug))

    recs =
      Health.state_recommendations_for_condition(condition.id, selected && selected.id, language)

    {:noreply,
     socket
     |> assign(:selected_state, selected)
     |> assign(:state_recommendations, recs)}
  end

  # Open the blueprint-preview modal for a dietary-pattern recommendation whose
  # name matched a public blueprint (e.g. "Mediterranean diet"). Loads the same
  # day/meal tree + sample plans the public preview page renders.
  def handle_event("open_blueprint", %{"slug" => slug}, socket) do
    blueprint = MealBlueprints.get_public_blueprint_by_slug!(slug)
    plans = MealBlueprints.list_public_plans_for_blueprint(blueprint.id)

    {:noreply,
     socket
     |> assign(:modal_blueprint, blueprint)
     |> assign(:modal_blueprint_plans, plans)}
  end

  def handle_event("close_blueprint", _params, socket) do
    {:noreply, assign(socket, :modal_blueprint, nil)}
  end

  # Saved-recipe ids for the current user (empty for guests).
  defp saved_recipe_ids(socket) do
    case socket.assigns[:current_user] do
      nil -> []
      user -> UserContent.list_user_saved_recipe_ids(user)
    end
  end

  # Prefer a Foundation-class ingredient (most complete nutrient data), else the
  # first; build its top-macro cards. Empty when the species has no ingredients.
  defp top_nutrients_for([]), do: []

  defp top_nutrients_for(ingredients) do
    selected =
      Enum.find(ingredients, &(&1.food_class == "Foundation")) || List.first(ingredients)

    build_top_nutrients(Food.get_ingredient_details!(selected.id).ingredient_nutrients)
  end

  # Up to 4 distinct recipes drawn from across the species' ingredients.
  defp sample_recipes_for(ingredients) do
    ingredients
    |> Enum.flat_map(&Food.list_sample_recipes_for_ingredient(&1.id, 4))
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(4)
  end

  # ── Partition helpers ────────────────────────────────────────────────────────

  @doc "Flagged species minus the encouraged ones (avoid/limit/caution/monitor)."
  def mindful_species(rows), do: Enum.reject(rows, &(&1.recommendation == "encourage"))

  @doc """
  Encouraged species, deduped (a species may be encouraged via >1 compound).

  A species that is also flagged as mindful (avoid/limit/caution/monitor via some
  other compound) is excluded — the mindful guidance takes precedence.
  """
  def encouraged_species(rows) do
    mindful_ids =
      rows
      |> mindful_species()
      |> MapSet.new(& &1.species.id)

    rows
    |> Enum.filter(&(&1.recommendation == "encourage"))
    |> Enum.reject(&MapSet.member?(mindful_ids, &1.species.id))
    |> Enum.uniq_by(& &1.species.id)
  end

  # schema.org nodes for this page, emitted as a single @graph in the head:
  #   • BreadcrumbList — mirrors the visible "Conditions › {name}" trail (breadcrumb
  #     rich result).
  #   • MedicalWebPage/MedicalCondition — semantic clarity that the page is dietary
  #     guidance about a condition (no visible card; YMYL, so kept purely descriptive).
  defp build_structured_data(condition, language, page_title, page_description) do
    conditions_url = "#{@base_url}/#{language}/conditions"
    condition_url = "#{conditions_url}/#{condition.id}"

    [
      %{
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{
            "@type" => "ListItem",
            "position" => 1,
            "name" => gettext("Conditions"),
            "item" => conditions_url
          },
          %{
            "@type" => "ListItem",
            "position" => 2,
            "name" => condition.name,
            "item" => condition_url
          }
        ]
      },
      %{
        "@type" => "MedicalWebPage",
        "name" => page_title,
        "url" => condition_url,
        "description" => page_description,
        "about" => %{"@type" => "MedicalCondition", "name" => condition.name},
        "audience" => %{"@type" => "MedicalAudience", "audienceType" => "Patient"}
      }
    ]
  end

  # Up to 10 random recipes that use at least one encouraged food and none of the
  # mindful ones. Encouraged/mindful species are disjoint (see `encouraged_species/1`),
  # so their ingredient sets don't overlap.
  defp recommended_recipes(species_rows) do
    encouraged_ids = encouraged_species(species_rows) |> Enum.map(& &1.species.id)
    mindful_ids = mindful_species(species_rows) |> Enum.map(& &1.species.id)

    case encouraged_ids do
      [] ->
        []

      _ ->
        include = Food.list_ingredient_ids_for_species(encouraged_ids)
        exclude = Food.list_ingredient_ids_for_species(mindful_ids)
        Food.list_random_recipes_including_excluding(include, exclude, 10)
    end
  end

  # ── View helpers (mirror SpeciesDetailLive.Index) ────────────────────────────

  @doc "The URL slug for a species — its English name with spaces hyphenated."
  def species_slug(%{name: name}), do: String.replace(name, " ", "-")

  @doc "Human label for a species↔compound relationship type."
  def relationship_label("contains"), do: "Contains"
  def relationship_label("high_in"), do: "High in"
  def relationship_label("low_in"), do: "Low in"
  def relationship_label("trace"), do: "Trace"
  def relationship_label("absent"), do: "Absent"
  def relationship_label(other), do: Phoenix.Naming.humanize(other || "")

  def format_amount(nil), do: "—"

  def format_amount(amount) when is_float(amount) do
    if amount >= 1 do
      amount |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    else
      amount |> Float.round(3) |> :erlang.float_to_binary(decimals: 3)
    end
  end

  def format_amount(amount), do: to_string(amount)

  defp build_top_nutrients(ingredient_nutrients) do
    by_name = Map.new(ingredient_nutrients, &{&1.nutrient.name, &1})

    @top_nutrient_names
    |> Enum.flat_map(fn name ->
      case Map.get(by_name, name) do
        nil ->
          []

        in_ ->
          unit =
            if in_.nutrient.measurement_unit, do: in_.nutrient.measurement_unit.name, else: ""

          [%{label: Map.get(@display_labels, name, name), amount: in_.amount, unit: unit}]
      end
    end)
  end

  # Groups recommendation rows by their `recommendation` value, ordered for display.
  def grouped_recommendations(recommendations) do
    recommendations
    |> Enum.group_by(& &1.recommendation)
    |> Enum.sort_by(fn {rec, _} -> group_order(rec) end)
  end

  defp group_order(rec) do
    case Enum.find_index(@recommendation_order, &(&1 == rec)) do
      nil -> length(@recommendation_order)
      idx -> idx
    end
  end

  @doc "Canonical PubMed URL for a study's PMID."
  def pubmed_url(pmid), do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  @doc "Display label for a reference study — its title, or a PMID fallback."
  def study_label(%{title: title}) when is_binary(title) and title != "", do: title
  def study_label(%{pmid: pmid}), do: "PMID #{pmid}"

  @doc """
  The clickable href for a structured `source_reference` (manual/guideline citation):
  its explicit `url`, else a PubMed link if it carries a `pmid`, else `nil`.
  """
  def reference_href(%{"url" => url}) when is_binary(url) and url != "", do: url
  def reference_href(%{"pmid" => pmid}) when not is_nil(pmid), do: pubmed_url(pmid)
  def reference_href(_), do: nil

  @doc "Display label for a structured `source_reference`."
  def reference_label(%{"label" => label}) when is_binary(label) and label != "", do: label
  def reference_label(%{"url" => url}) when is_binary(url) and url != "", do: url
  def reference_label(%{"pmid" => pmid}) when not is_nil(pmid), do: "PMID #{pmid}"
  def reference_label(_), do: gettext("Source")

  @doc """
  The slug of a public blueprint whose name matches `name` (from the
  `@blueprint_links` lookup), or `nil`. Used to linkify a dietary-pattern
  recommendation title to its preview modal.
  """
  def blueprint_slug(links, name) when is_map(links) and is_binary(name),
    do: Map.get(links, name |> String.trim() |> String.downcase())

  def blueprint_slug(_links, _name), do: nil

  def recommendation_label("avoid"), do: gettext("Avoid")
  def recommendation_label("limit"), do: gettext("Limit")
  def recommendation_label("caution"), do: gettext("Approach with caution")
  def recommendation_label("monitor"), do: gettext("Monitor")
  def recommendation_label("encourage"), do: gettext("Encourage")
  def recommendation_label(rec), do: String.capitalize(rec)

  # Gettext-translated label for a top-macro nutrient card (canonical English key
  # from `@display_labels`); explicit clauses so `mix gettext.extract` sees them.
  def nutrient_label("Calories"), do: gettext("Calories")
  def nutrient_label("Protein"), do: gettext("Protein")
  def nutrient_label("Fat"), do: gettext("Fat")
  def nutrient_label("Carbs"), do: gettext("Carbs")
  def nutrient_label("Fiber"), do: gettext("Fiber")
  def nutrient_label(other), do: other

  # Overlays the species' translated name for the modal title. A locale maps to
  # several `language_name` codes (ISO + legacy, e.g. "el"/"Gr"); species rows
  # often predate the ISO migration and live under "Gr", so we try every code for
  # the locale (canonical ISO first). `nil`/`"en"` leaves the base English name.
  defp localize_species_name(species, language) when language in [nil, "", "en"], do: species

  defp localize_species_name(species, language) do
    Mehungry.Languages.Locale.data_codes(language)
    |> Enum.find_value(fn code ->
      case Food.find_species_translation(code, species.id) do
        [name | _] -> name
        [] -> nil
      end
    end)
    |> case do
      nil -> species
      name -> %{species | name: name}
    end
  end
end
