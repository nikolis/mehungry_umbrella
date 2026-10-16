defmodule MehungryWeb.SpeciesDetailLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesCompounds
  alias Phoenix.LiveView.AsyncResult

  @base_url "https://www.m3hungry.com"

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

  # ═══════════════════════════════════════════════════════════════════════════
  # Update (mount / events)
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    maybe_track_user(%{}, socket)

    case Food.get_species_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/foods")}

      species ->
        language = socket.assigns[:current_language] || "en"

        display_name =
          if language == "el" do
            case Food.find_species_translation("el", species.id) do
              [greek_name | _] -> greek_name
              [] -> species.name
            end
          else
            species.name
          end

        ingredients = species_ingredients(species)
        selected = default_ingredient(ingredients)

        page_title = "#{display_name} — Nutrition, Research & Compounds"

        page_description =
          "#{display_name}: nutrition facts across its foods, the research behind it, and the bioactive compounds it carries."

        socket =
          socket
          |> assign(:species, species)
          |> assign(:display_name, display_name)
          |> assign(:ingredients, ingredients)
          |> assign(:evidence_modal, nil)
          |> assign_ingredient_view(selected && selected.id)
          |> load_species_sidecars(species)
          |> assign(:page_title, page_title)
          |> assign(:page_description, page_description)

        # JSON-LD for the dead render (crawler-visible). The nutrition node reflects
        # the default-selected ingredient's tree — the one rendered on first paint;
        # switching ingredients happens over the socket, after the head is sent.
        {:ok,
         assign(
           socket,
           :structured_data,
           build_structured_data(
             species,
             socket.assigns.nutrient_tree,
             display_name,
             language,
             page_title,
             page_description
           )
         )}
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
    if connected?(socket) do
      assign_async(socket, [:compounds], fn ->
        {:ok, %{compounds: SpeciesCompounds.list_species_relationships(species.id)}}
      end)
    else
      assign(
        socket,
        :compounds,
        AsyncResult.ok(SpeciesCompounds.list_species_relationships(species.id))
      )
    end
  end

  @impl true
  def handle_event("select_ingredient", %{"id" => id}, socket) do
    {:noreply, assign_ingredient_view(socket, parse_id(id))}
  end

  # The supporting-research modal for one species↔compound fact. Studies are
  # deliberately fetched here — on click — rather than preloaded with the
  # compound list, so the initial page paint carries no PubMed provenance rows.
  @impl true
  def handle_event("show_evidence", %{"rel-id" => rel_id, "compound" => name}, socket) do
    studies = SpeciesCompounds.list_relationship_studies(parse_id(rel_id))

    {:noreply, assign(socket, :evidence_modal, %{compound: name, studies: studies})}
  end

  @impl true
  def handle_event("close_evidence", _params, socket) do
    {:noreply, assign(socket, :evidence_modal, nil)}
  end

  # The ingredient `{id, name}` options + the selected ingredient's nutrient view.
  defp assign_ingredient_view(socket, nil) do
    socket
    |> assign(:selected_ingredient, nil)
    |> assign(:top_nutrients, [])
    |> assign(:nutrient_tree, %{})
    |> assign(:composition_summary, nil)
  end

  defp assign_ingredient_view(socket, ingredient_id) do
    ingredient = Food.get_ingredient_details!(ingredient_id)

    # Same string-keyed, hierarchical per-100g tree recipes persist and the
    # calendar "Nutrition Facts" accordion consumes (gram_weight 100 => factor
    # 1.0), so this breakdown renders identically — fat/carb/vitamin/mineral
    # groups foldable — for whichever connected ingredient the dropdown selects.
    nutrient_tree = Mehungry.Food.NutrientCalculation.ingredient_nutrient_tree(ingredient, 100)

    socket
    |> assign(:selected_ingredient, ingredient)
    |> assign(:top_nutrients, build_top_nutrients(ingredient.ingredient_nutrients))
    |> assign(:nutrient_tree, nutrient_tree)
    |> assign(:composition_summary, build_composition_summary(ingredient.name, nutrient_tree))
  end

  defp species_ingredients(species) do
    species.foundemental_foods
    |> Enum.map(& &1.ingredient)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.name)
  end

  # Prefer a Foundation-class ingredient (most complete nutrient data), else the first.
  defp default_ingredient([]), do: nil

  defp default_ingredient(ingredients) do
    Enum.find(ingredients, &(&1.food_class == "Foundation")) || hd(ingredients)
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  # ═══════════════════════════════════════════════════════════════════════════
  # View helpers
  # ═══════════════════════════════════════════════════════════════════════════

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

  # ── Composition summary ──────────────────────────────────────────────────
  # One short paragraph of deterministic, indexable prose for the selected
  # ingredient. Server-rendered (crawlable); the long-tail nutrient terms
  # (sugar/fat names) are the SEO payload, kept to a sentence or two so the page
  # stays uncluttered.
  defp build_composition_summary(_name, tree) when map_size(tree) == 0, do: nil

  defp build_composition_summary(name, tree) do
    carbs = top_amount(tree, "Carbohydrates")
    fat = top_amount(tree, "Total Fat")
    protein = top_amount(tree, "Protein")
    energy = top_amount(tree, "Energy")

    macro_parts =
      [{"carbohydrate", carbs}, {"fat", fat}, {"protein", protein}]
      |> Enum.filter(fn {_label, amount} -> is_number(amount) and amount > 0 end)
      |> Enum.map(fn {label, amount} -> "#{format_amount(amount)} g of #{label}" end)

    energy_prefix =
      if is_number(energy) and energy > 0, do: "#{format_amount(energy)} kcal with ", else: ""

    lead =
      case macro_parts do
        [] -> nil
        parts -> "Per 100 g, #{name} provides #{energy_prefix}#{join_and(parts)}."
      end

    [lead, sugar_sentence(tree, carbs), fat_sentence(tree, fat)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      sentences -> Enum.join(sentences, " ")
    end
  end

  defp sugar_sentence(tree, carbs) do
    carbs_node = top_node(tree, "Carbohydrates")
    sugars = node_amount(find_desc(carbs_node, ["Total Sugars"]))

    cond do
      not (is_number(sugars) and sugars > 0) ->
        nil

      is_number(carbs) and carbs > 0 and sugars / carbs >= 0.8 ->
        "Those carbohydrates are almost entirely sugars (#{format_amount(sugars)} g)#{leading_sugar_suffix(carbs_node)}."

      true ->
        "It contains #{format_amount(sugars)} g of total sugars#{leading_sugar_suffix(carbs_node)}."
    end
  end

  @sugar_names ["Fructose", "Glucose", "Galactose", "Sucrose", "Lactose", "Maltose"]

  defp leading_sugar_suffix(carbs_node) do
    carbs_node
    |> collect_nodes()
    |> Enum.filter(fn {n, a} -> n in @sugar_names and a > 0 end)
    |> Enum.sort_by(fn {_n, a} -> -a end)
    |> Enum.take(2)
    |> case do
      [] -> ""
      list -> ", led by " <> join_and(Enum.map(list, fn {n, _a} -> String.downcase(n) end))
    end
  end

  defp fat_sentence(tree, fat) when is_number(fat) and fat >= 1.0 do
    node = top_node(tree, "Total Fat")
    sat = child_amount(node, "Saturated Fat") || 0.0

    unsat =
      (child_amount(node, "Monounsaturated Fat") || 0.0) +
        (child_amount(node, "Polyunsaturated Fat") || 0.0)

    cond do
      unsat > sat and unsat > 0 -> "Its fat is mostly unsaturated."
      sat > unsat and sat > 0 -> "Its fat is mostly saturated."
      true -> nil
    end
  end

  defp fat_sentence(_tree, _fat), do: nil

  # ── JSON-LD structured data (head reads @structured_data) ─────────────────
  # BreadcrumbList (the real rich-result win, mirrors the visible "Foods › name"
  # trail) + a WebPage whose MenuItem mainEntity carries a NutritionInformation.
  # NutritionInformation has NO schema.org fields for individual sugars or fatty
  # acids, so JSON-LD intentionally covers macros / level-1 only — the deep
  # breakdown's SEO value comes from the crawlable visible text, not here.
  defp build_structured_data(species, tree, name, language, title, description) do
    foods_url = "#{@base_url}/#{language}/foods"
    food_url = "#{foods_url}/#{species_slug(species)}"

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
      [child_amount(fat_node, "Monounsaturated Fat"), child_amount(fat_node, "Polyunsaturated Fat")]
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

  @doc "The URL slug for a species — its name with spaces hyphenated."
  def species_slug(%{name: name}), do: String.replace(name || "", " ", "-")

  # ── String-keyed nutrient-tree accessors ──────────────────────────────────
  defp top_node(tree, name) when is_map(tree), do: Map.get(tree, name)
  defp top_node(_tree, _name), do: nil

  defp top_amount(tree, name), do: node_amount(top_node(tree, name))

  defp child_node(node, name) when is_map(node) do
    Enum.find(node["children"] || [], &(&1["name"] == name))
  end

  defp child_node(_node, _name), do: nil

  defp child_amount(node, name), do: node_amount(child_node(node, name))

  # First descendant (self included) whose name is in `names`, searching children.
  defp find_desc(nil, _names), do: nil

  defp find_desc(node, names) when is_map(node) do
    if node["name"] in names do
      node
    else
      Enum.find_value(node["children"] || [], &find_desc(&1, names))
    end
  end

  # {name, amount} for this node and every descendant that has a numeric amount.
  defp collect_nodes(nil), do: []

  defp collect_nodes(node) when is_map(node) do
    self_entry =
      case {node["name"], node["amount"]} do
        {n, a} when is_binary(n) and is_number(a) -> [{n, a}]
        _ -> []
      end

    self_entry ++ Enum.flat_map(node["children"] || [], &collect_nodes/1)
  end

  defp node_amount(node) when is_map(node) do
    case node["amount"] do
      a when is_number(a) -> a
      _ -> nil
    end
  end

  defp node_amount(_), do: nil

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

  # Standard schema.org nutrition unit abbreviations.
  defp normalize_unit("kilocalorie"), do: "kcal"
  defp normalize_unit("kcal"), do: "kcal"
  defp normalize_unit("gram"), do: "g"
  defp normalize_unit("milligram"), do: "mg"
  defp normalize_unit("microgram"), do: "µg"
  defp normalize_unit(unit) when is_binary(unit), do: unit
  defp normalize_unit(_), do: ""

  defp join_and([]), do: ""
  defp join_and([only]), do: only

  defp join_and(list) do
    {init, [last]} = Enum.split(list, length(list) - 1)
    Enum.join(init, ", ") <> " and " <> last
  end

  def format_amount(nil), do: "—"

  def format_amount(amount) when is_float(amount) do
    if amount >= 1 do
      amount |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    else
      amount |> Float.round(3) |> :erlang.float_to_binary(decimals: 3)
    end
  end

  def format_amount(amount), do: to_string(amount)

  @doc "PubMed permalink for a study's PMID."
  def pubmed_url(%{pmid: pmid}) when not is_nil(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}"

  def pubmed_url(_), do: nil

  @doc "Human label for a species↔compound relationship type."
  def relationship_label("contains"), do: "Contains"
  def relationship_label("high_in"), do: "High in"
  def relationship_label("low_in"), do: "Low in"
  def relationship_label("trace"), do: "Trace"
  def relationship_label("absent"), do: "Absent"
  def relationship_label(other), do: Phoenix.Naming.humanize(other || "")
end
