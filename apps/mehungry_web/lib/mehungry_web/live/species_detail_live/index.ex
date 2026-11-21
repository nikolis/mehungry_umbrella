defmodule MehungryWeb.SpeciesDetailLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  alias Mehungry.FactMining
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesNutritionSummary
  alias Mehungry.Literature.ResearchType
  alias Phoenix.LiveView.AsyncResult

  @base_url "https://www.m3hungry.com"

  # ═══════════════════════════════════════════════════════════════════════════
  # Update (mount / events)
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    maybe_track_user(%{}, socket)

    case Food.get_species_by_slug(slug) do
      nil ->
        # A missing food must be a real 404, never a 302 to /foods — redirecting a
        # dead URL to the catalog is a soft-404 that wastes crawl budget and can
        # suppress the whole /foods/:slug pattern in search. Raising
        # Ecto.NoResultsError renders the 404 on the disconnected (crawler) render
        # via Plug.Exception.
        raise Ecto.NoResultsError, queryable: Mehungry.Food.FoundementalFoodSpecies

      species ->
        language = socket.assigns[:current_language] || "en"

        el_name =
          case Food.find_species_translation("el", species.id) do
            [greek_name | _] -> greek_name
            _ -> nil
          end

        display_name = if language == "el" and el_name, do: el_name, else: species.name

        # One canonical slug per locale, derived from the species (not from the
        # slug the request happened to use), so every variant — /foods/Beef,
        # /en/foods/Beef, /el/foods/Beef, /el/foods/Βοδινό-κρέας — consolidates
        # onto a single URL per language and the hreflang pair is reciprocal.
        # Fixes the Greek duplicate-canonical fold (Κάρδαμο → Cress). `head`
        # reads :canonical_path + :hreflang_paths off the dead-render conn.
        en_slug = species_slug(species)
        el_slug = if el_name, do: species_slug(%{name: el_name}), else: en_slug
        cur_slug = if language == "el", do: el_slug, else: en_slug
        hreflang_paths = %{"en" => "/foods/" <> en_slug, "el" => "/foods/" <> el_slug}

        ingredients = SpeciesNutritionSummary.species_ingredients(species)
        selected = SpeciesNutritionSummary.default_ingredient(ingredients)

        socket =
          socket
          |> assign(:species, species)
          |> assign(:display_name, display_name)
          |> assign(:ingredients, ingredients)
          |> assign_ingredient_view(selected && selected.id)
          |> load_species_sidecars(species)

        # Title + description lead with the query intent the GSC data shows
        # (calories / protein / fat "per 100g") and the description carries the
        # real macro numbers — numbers in the snippet lift CTR on nutrient queries.
        page_title = "#{display_name} Calories & Nutrition Facts (per 100g)"
        page_description = seo_description(display_name, socket.assigns.top_nutrients)

        socket =
          socket
          |> assign(:page_title, page_title)
          |> assign(:page_description, page_description)
          |> assign(:canonical_path, "/foods/" <> cur_slug)
          |> assign(:hreflang_paths, hreflang_paths)

        # JSON-LD for the dead render (crawler-visible). The nutrition node reflects
        # the default-selected ingredient's tree — the one rendered on first paint;
        # switching ingredients happens over the socket, after the head is sent.
        {:ok,
         assign(
           socket,
           :structured_data,
           build_structured_data(
             socket.assigns.nutrient_tree,
             display_name,
             language,
             cur_slug,
             page_title,
             page_description
           )
         )}
    end
  end

  # One-line meta description carrying the selected ingredient's real per-100g
  # macros ("Beef per 100 g: 291 kcal, 24 g protein, 19 g fat. …"). Zero/absent
  # macros are dropped so we never assert a fabricated number.
  defp seo_description(name, top_nutrients) do
    by_label = Map.new(top_nutrients, &{&1.label, &1.amount})

    parts =
      [{"Calories", "kcal"}, {"Protein", "g protein"}, {"Carbs", "g carbs"}, {"Fat", "g fat"}]
      |> Enum.flat_map(fn {label, unit} ->
        case Map.get(by_label, label) do
          amount when is_number(amount) and amount > 0 -> ["#{format_macro(amount)} #{unit}"]
          _ -> []
        end
      end)

    case parts do
      [] ->
        "#{name}: full USDA nutrition facts per 100 g — calories, protein, carbs, fat, vitamins, minerals and the research behind it, on M3Hungry."

      _ ->
        "#{name} per 100 g: #{Enum.join(parts, ", ")}. Full USDA nutrition facts — vitamins, minerals and research on M3Hungry."
    end
  end

  # Compounds are secondary to the (synchronous) nutrition facts, so the live
  # client loads them asynchronously for a fast paint. On the disconnected
  # ("dead") render Googlebot indexes — it never opens the LiveView WebSocket —
  # that async assign would stay in its loading state and render as skeletons,
  # hiding the "Compounds" section the page title advertises. So on the dead
  # render we load it synchronously and hand the template a resolved
  # `AsyncResult`.
  defp load_species_sidecars(socket, species) do
    language = socket.assigns[:current_language] || "en"
    ingredient_ids = Enum.map(socket.assigns.ingredients, & &1.id)

    # Enrichment facts (origin / producers / description) are a tiny read and must be in
    # the dead render crawlers index, so they're assigned synchronously on both renders
    # (unlike the heavier compounds/recipes, which go async when connected).
    socket = assign(socket, :facts, Food.promoted_species_facts_for_species(species.id, language))

    # `@research` is now the *curated* set — the on-subject verified top 10, not the
    # full (potentially thousands-strong) fact list. That is the SEO-visible payload
    # and the first paint; the rest is reached via the search box (search_research).
    # The verdict tally reads a cheap grouped count, so it still reports the true
    # totals. Search state starts empty.
    name_term = FactMining.species_name_term(species)

    socket =
      socket
      |> assign(:research_counts, FactMining.research_counts_for_species(species.id))
      |> assign(:recipes_count, Food.count_recipes_for_ingredients(ingredient_ids))
      |> assign(:research_query, "")
      |> assign(:research_results, [])

    if connected?(socket) do
      assign_async(socket, [:research, :recipes], fn ->
        {:ok,
         %{
           research: FactMining.curated_facts_for_species(species.id, name_term: name_term),
           recipes: Food.list_sample_recipes_for_ingredients(ingredient_ids)
         }}
      end)
    else
      socket
      |> assign(
        :research,
        AsyncResult.ok(FactMining.curated_facts_for_species(species.id, name_term: name_term))
      )
      |> assign(
        :recipes,
        AsyncResult.ok(Food.list_sample_recipes_for_ingredients(ingredient_ids))
      )
    end
  end

  # ── Enrichment facts (Origins & cultivation section) ─────────────────────────
  # `@facts` is a fact_key => SpeciesFact map from `promoted_species_facts_for_species/2`.

  @doc "The text of a single-value fact (origin_region / description / wikipedia_url), else nil."
  def fact_text(facts, key) do
    case facts[key] do
      %{value_text: text} when is_binary(text) and text != "" -> text
      _ -> nil
    end
  end

  @doc "Ranked producing-country names from the top_producers fact (names only — tonnage isn't shown)."
  def producer_countries(facts) do
    case facts["top_producers"] do
      %{value_json: %{"producers" => producers}} when is_list(producers) ->
        producers |> Enum.map(& &1["country"]) |> Enum.reject(&(&1 in [nil, ""]))

      _ ->
        []
    end
  end

  @doc "The source year of the top_producers fact, for the FAOSTAT credit line."
  def producers_year(facts) do
    case facts["top_producers"] do
      %{value_json: %{"producers" => [%{"year" => year} | _]}} -> year
      _ -> nil
    end
  end

  @doc "Whether any enrichment fact is present, to decide whether to render the section."
  def enrichment?(facts) do
    not is_nil(fact_text(facts, "origin_region")) or
      not is_nil(fact_text(facts, "description")) or
      not is_nil(fact_text(facts, "wikipedia_url")) or
      producer_countries(facts) != []
  end

  @impl true
  def handle_event("select_ingredient", %{"id" => id}, socket) do
    {:noreply, assign_ingredient_view(socket, parse_id(id))}
  end

  # Fuzzy search over the full fact set — the on-demand path for everything the
  # curated top-10 omits (contradicted + unverified + off-subject findings). A
  # blank query falls back to the curated set (empty results list).
  def handle_event("search_research", %{"q" => q}, socket) do
    results = FactMining.search_facts_for_species(socket.assigns.species.id, q)
    {:noreply, assign(socket, research_query: q, research_results: results)}
  end

  # The ingredient `{id, name}` options + the selected ingredient's nutrient view.
  defp assign_ingredient_view(socket, nil) do
    socket
    |> assign(:selected_ingredient, nil)
    |> assign(:top_nutrients, [])
    |> assign(:nutrient_tree, %{})
    |> assign(:composition_summary, nil)
    |> assign(:micronutrient_summary, nil)
  end

  defp assign_ingredient_view(socket, ingredient_id) do
    ingredient = Food.get_ingredient_details!(ingredient_id)

    # Same string-keyed, hierarchical per-100g tree recipes persist and the
    # calendar "Nutrition Facts" accordion consumes (gram_weight 100 => factor
    # 1.0), so this breakdown renders identically — fat/carb/vitamin/mineral
    # groups foldable — for whichever connected ingredient the dropdown selects.
    nutrient_tree = Mehungry.Food.NutrientCalculation.ingredient_nutrient_tree(ingredient, 100)

    micro_name = socket.assigns[:display_name] || ingredient.name

    socket
    |> assign(:selected_ingredient, ingredient)
    |> assign(
      :top_nutrients,
      SpeciesNutritionSummary.top_nutrients(ingredient.ingredient_nutrients)
    )
    |> assign(
      :composition_summary,
      SpeciesNutritionSummary.composition_summary(ingredient.name, nutrient_tree)
    )
    |> assign(:nutrient_tree, nutrient_tree)
    |> assign(
      :micronutrient_summary,
      SpeciesNutritionSummary.micronutrient_summary(micro_name, nutrient_tree)
    )
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  # ═══════════════════════════════════════════════════════════════════════════
  # View helpers
  # ═══════════════════════════════════════════════════════════════════════════

  # ── JSON-LD structured data (head reads @structured_data) ─────────────────
  # BreadcrumbList (the real rich-result win, mirrors the visible "Foods › name"
  # trail) + a WebPage whose MenuItem mainEntity carries a NutritionInformation.
  # NutritionInformation has NO schema.org fields for individual sugars or fatty
  # acids, so JSON-LD intentionally covers macros / level-1 only — the deep
  # breakdown's SEO value comes from the crawlable visible text, not here.
  defp build_structured_data(tree, name, language, slug, title, description) do
    foods_url = "#{@base_url}/#{language}/foods"
    food_url = "#{foods_url}/#{slug}"

    [
      %{
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{"@type" => "ListItem", "position" => 1, "name" => "Foods", "item" => foods_url},
          %{"@type" => "ListItem", "position" => 2, "name" => name, "item" => food_url}
        ]
      },
      %{
        "@type" => "WebPage",
        "name" => title,
        "url" => food_url,
        "description" => description,
        "mainEntity" => %{
          "@type" => "MenuItem",
          "name" => name,
          "nutrition" => nutrition_information(tree)
        }
      }
    ]
  end

  defp nutrition_information(tree) do
    fat_node = top_node(tree, "Total Fat")
    carbs_node = top_node(tree, "Carbohydrates")

    unsat =
      [
        child_amount(fat_node, "Monounsaturated Fat"),
        child_amount(fat_node, "Polyunsaturated Fat")
      ]
      |> Enum.filter(&is_number/1)
      |> Enum.sum()

    %{"@type" => "NutritionInformation", "servingSize" => "100 g"}
    |> put_nutrient("calories", top_node(tree, "Energy"))
    |> put_nutrient("proteinContent", top_node(tree, "Protein"))
    |> put_nutrient("fatContent", fat_node)
    |> put_nutrient("saturatedFatContent", child_node(fat_node, "Saturated Fat"))
    |> put_nutrient("transFatContent", child_node(fat_node, "Trans Fat"))
    |> maybe_put("unsaturatedFatContent", if(unsat > 0, do: "#{format_amount(unsat)} g"))
    |> put_nutrient("carbohydrateContent", carbs_node)
    |> put_nutrient("sugarContent", find_desc(carbs_node, ["Total Sugars"]))
    |> put_nutrient(
      "fiberContent",
      find_desc(carbs_node, ["Fiber", "Dietary Fiber", "Fiber, total dietary"])
    )
    |> put_nutrient("sodiumContent", find_desc(top_node(tree, "Minerals"), ["Sodium"]))
    |> put_nutrient("cholesterolContent", top_node(tree, "Cholesterol"))
  end

  defp put_nutrient(map, key, node) do
    case node_grams(node) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "The URL slug for a species — the shared clean, decode-tolerant slug."
  def species_slug(%{name: name}), do: Food.species_slug(name || "")

  # String-keyed nutrient-tree accessors + formatting live in the shared
  # `SpeciesNutritionSummary` (also used by the mobile API).
  defdelegate top_node(tree, name), to: SpeciesNutritionSummary
  defdelegate child_node(node, name), to: SpeciesNutritionSummary
  defdelegate child_amount(node, name), to: SpeciesNutritionSummary
  defdelegate find_desc(node, names), to: SpeciesNutritionSummary
  defdelegate normalize_unit(unit), to: SpeciesNutritionSummary
  defdelegate format_amount(amount), to: SpeciesNutritionSummary
  defdelegate macro_unit(unit), to: SpeciesNutritionSummary

  # "<amount> <unit>" for schema.org, or nil for a missing / non-positive node.
  defp node_grams(node) when is_map(node) do
    amount = node["amount"]

    if is_number(amount) and amount > 0 do
      unit = normalize_unit(node["measurement_unit"])
      unit_suffix = if unit != "", do: " #{unit}", else: ""
      "#{format_amount(amount)}#{unit_suffix}"
    end
  end

  defp node_grams(_), do: nil

  @doc """
  Headline-macro formatting for the stat cards: at most one decimal, with a
  trailing `.0` stripped (`341.0 → "341"`, `0.69 → "0.7"`, `1.7 → "1.7"`). Keeps
  the row visually even — unlike `format_amount/1`, which widens sub-1 values to
  three decimals (right for a micronutrient cell, wrong beside `341`).
  """
  def format_macro(nil), do: "—"

  def format_macro(amount) when is_float(amount) do
    rounded = Float.round(amount, 1)

    if rounded == Float.round(amount, 0) do
      rounded |> trunc() |> Integer.to_string()
    else
      :erlang.float_to_binary(rounded, decimals: 1)
    end
  end

  def format_macro(amount) when is_integer(amount), do: Integer.to_string(amount)
  def format_macro(amount), do: to_string(amount)

  @doc "PubMed permalink for a study's PMID."
  def pubmed_url(%{pmid: pmid}) when not is_nil(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}"

  def pubmed_url(_), do: nil

  # ── Research findings: verdict-led "evidence ledger" ──────────────────────
  # Every mined fact carries an honest verification `label`; the section groups
  # them by verdict (the credibility axis) and ranks within a group by human
  # relevance (`claim_type`: a treatment outcome beats a lab mechanism) then
  # evidence strength (`study_design` via the shared ResearchType pyramid). The
  # readable Verified group leads; the disputed + unverified tail collapses.

  @doc "Human label for a mined fact's verification state (its nuanced, localized wording)."
  def research_label("verified"), do: gettext("Corroborated")
  def research_label("contradicted"), do: gettext("Contradicted")
  def research_label("unverified_quality"), do: gettext("Unverified — study quality")
  def research_label("unverified_fulltext"), do: gettext("Unverified — abstract only")
  def research_label("unverified_insufficient"), do: gettext("Unverified — too few studies")
  def research_label("unverified_verification"), do: gettext("Unverified — not confirmed")
  def research_label(other), do: Phoenix.Naming.humanize(other || "")

  @doc "Coarse verdict group (credibility axis) for a mined fact's `label`."
  def verdict_group("verified"), do: :verified
  def verdict_group("contradicted"), do: :contradicted
  def verdict_group(_unverified), do: :unverified

  @doc "Accent classes (left rail colour + badge colours) per verdict group."
  def verdict_accent(:verified), do: %{rail: "bg-basil", badge: "bg-basil/15 text-basil"}

  def verdict_accent(:contradicted),
    do: %{rail: "bg-paprika", badge: "bg-paprika/15 text-paprika"}

  def verdict_accent(:unverified),
    do: %{rail: "bg-parchment-dim/30", badge: "bg-ink-panel2 text-parchment-dim"}

  # Short, acronym-correct study-design chip label ("RCT", "Mechanistic"), not the
  # mis-cased `Phoenix.Naming.humanize("rct") => "Rct"`. nil/unknown → no chip.
  @study_design_labels %{
    "rct" => "RCT",
    "mechanistic_experiment" => "Mechanistic",
    "systematic_review" => "Systematic review",
    "meta_analysis" => "Meta-analysis",
    "cohort" => "Cohort study",
    "case_control" => "Case–control",
    "cross_sectional" => "Cross-sectional",
    "case_report" => "Case report",
    "gwas" => "GWAS"
  }

  @doc "Short display label for a `study_design`, or nil when unknown/blank."
  def study_design_label(design) when design in [nil, "", "unknown"], do: nil

  def study_design_label(design),
    do: Map.get(@study_design_labels, design, Phoenix.Naming.humanize(design))

  @doc "Whether a study design is a human controlled trial — worth highlighting."
  def rct?(design), do: ResearchType.bucket(design) == :controlled_trial

  # ── Lead-photo credit ─────────────────────────────────────────────────────
  # The species photo is a licence-gated Wikimedia Commons image; we always show a
  # credit next to it (author · licence · source) — even for CC0/public-domain, where
  # attribution isn't strictly required — because we chose to display it.
  attr :species, :map, required: true

  def species_photo_credit(assigns) do
    ~H"""
    <p class="mt-2 text-xs text-parchment-dim/70">
      {gettext("Photo")}<span :if={present?(@species.image_attribution)}>: {@species.image_attribution}</span>
      <span :if={present?(@species.image_license)} aria-hidden="true">·</span>
      <a
        :if={present?(@species.image_license) && present?(@species.image_license_url)}
        href={@species.image_license_url}
        target="_blank"
        rel="noopener nofollow"
        class="underline hover:text-parchment"
      >{@species.image_license}</a>
      <span :if={present?(@species.image_license) && !present?(@species.image_license_url)}>
        {@species.image_license}
      </span>
      <span aria-hidden="true">·</span>
      <a
        href={@species.image_source_url}
        target="_blank"
        rel="noopener nofollow"
        class="underline hover:text-parchment"
      >{gettext("via Wikimedia Commons")}</a>
    </p>
    """
  end

  defp present?(value), do: is_binary(value) and value != ""

  # ── Research-finding row (shared by the curated + search lists) ───────────
  attr :fact, :map, required: true

  def research_fact(assigns) do
    assigns =
      assign(assigns,
        group: verdict_group(assigns.fact.label),
        design: study_design_label(assigns.fact.study_design)
      )

    ~H"""
    <li class="flex gap-3 bg-ink-panel border border-ink-panel2 rounded-xl p-4">
      <span
        class={"w-1 shrink-0 self-stretch rounded-full #{verdict_accent(@group).rail}"}
        aria-hidden="true"
      />
      <div class="min-w-0 flex-1">
        <div class="flex flex-col-reverse sm:flex-row sm:items-start sm:justify-between gap-1.5 sm:gap-3">
          <p class="text-sm text-parchment leading-relaxed">{@fact.text}</p>
          <span class={"self-start shrink-0 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium #{verdict_accent(@group).badge}"}>
            <.verdict_icon group={@group} />
            {research_label(@fact.label)}
          </span>
        </div>
        <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-parchment-dim">
          <span
            :if={@design}
            class={[
              "inline-flex items-center rounded px-1.5 py-0.5 font-medium",
              if(rct?(@fact.study_design),
                do: "bg-basil/10 text-basil-soft",
                else: "bg-ink-panel2 text-parchment-dim"
              )
            ]}
          >
            {@design}
          </span>
          <a
            :if={pubmed_url(@fact)}
            href={pubmed_url(@fact)}
            target="_blank"
            rel="noopener"
            class="underline decoration-dotted underline-offset-2 hover:text-paprika-soft transition-colors"
          >
            PMID {@fact.pmid}
          </a>
        </div>
        <%!-- Native <details> — no JS, keyboard-accessible, and the reason stays in
             the crawlable DOM. --%>
        <details :if={@fact.reason not in [nil, ""]} class="group/why mt-2 text-xs">
          <summary class="inline-flex items-center gap-0.5 cursor-pointer list-none text-parchment-dim hover:text-parchment transition-colors [&::-webkit-details-marker]:hidden">
            {gettext("Why?")}
            <svg
              class="w-3 h-3 transition-transform group-open/why:rotate-180"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              viewBox="0 0 24 24"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
            </svg>
          </summary>
          <p class="mt-2 border-t border-ink-panel2 pt-2 text-parchment-dim/90 leading-relaxed">
            {@fact.reason}
          </p>
        </details>
      </div>
    </li>
    """
  end

  # Tiny verdict glyph for the badge: check / cross / dash.
  attr :group, :atom, required: true

  def verdict_icon(%{group: :verified} = assigns) do
    ~H"""
    <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
    </svg>
    """
  end

  def verdict_icon(%{group: :contradicted} = assigns) do
    ~H"""
    <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
    </svg>
    """
  end

  def verdict_icon(assigns) do
    ~H"""
    <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="7" />
    </svg>
    """
  end
end
