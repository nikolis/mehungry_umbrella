defmodule MehungryWeb.SpeciesDetailLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesCompounds
  alias Phoenix.LiveView.AsyncResult

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

        {:ok,
         socket
         |> assign(:species, species)
         |> assign(:display_name, display_name)
         |> assign(:ingredients, ingredients)
         |> assign(:evidence_modal, nil)
         |> assign_ingredient_view(selected && selected.id)
         |> load_species_sidecars(species)
         |> assign(:page_title, "#{display_name} — Nutrition, Research & Compounds")
         |> assign(
           :page_description,
           "#{display_name}: nutrition facts across its foods, the research behind it, and the bioactive compounds it carries."
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
    |> assign(:nutrients_by_family, [])
  end

  defp assign_ingredient_view(socket, ingredient_id) do
    ingredient = Food.get_ingredient_details!(ingredient_id)

    socket
    |> assign(:selected_ingredient, ingredient)
    |> assign(:top_nutrients, build_top_nutrients(ingredient.ingredient_nutrients))
    |> assign(:nutrients_by_family, group_by_family(ingredient.ingredient_nutrients))
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

  defp group_by_family(ingredient_nutrients) do
    ingredient_nutrients
    |> Enum.reject(&zero_amount?(&1.amount))
    |> Enum.sort_by(& &1.nutrient.rank)
    |> Enum.group_by(&(&1.nutrient.family || "Other"))
    |> Enum.sort_by(fn {family, _} -> family_sort_order(family) end)
  end

  # A nutrient reads as "zero" when it rounds to 0.000 at the 3-decimal precision we
  # display — those rows carry no information, so they are dropped from the breakdown.
  defp zero_amount?(nil), do: true
  defp zero_amount?(amount) when is_number(amount), do: Float.round(amount / 1, 3) == 0.0
  defp zero_amount?(_), do: true

  defp family_sort_order("Proximates"), do: 0
  defp family_sort_order("Lipids"), do: 1
  defp family_sort_order("Minerals"), do: 2
  defp family_sort_order("Vitamins and Other Components"), do: 3
  defp family_sort_order("Amino Acids"), do: 4
  defp family_sort_order(_), do: 5

  def format_amount(nil), do: "—"

  def format_amount(amount) when is_float(amount) do
    if amount >= 1 do
      amount |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    else
      amount |> Float.round(3) |> :erlang.float_to_binary(decimals: 3)
    end
  end

  def format_amount(amount), do: to_string(amount)

  def nutrient_unit(%{nutrient: %{measurement_unit: %{name: name}}}), do: name
  def nutrient_unit(_), do: ""

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
